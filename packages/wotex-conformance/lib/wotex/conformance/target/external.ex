defmodule Wotex.Conformance.Target.External do
  @moduledoc """
  Direct external executable target for immutable archive conformance.

  One process is started per vector. It receives one canonical JSON request on
  standard input, emits one JSON response on standard output, and exits. No
  shell is involved. The inherited environment is removed before the supplied
  bounded environment is applied.

  The invocation uses one monotonic deadline and non-suspending port writes.
  Every opened port is closed on return, including write and decoding failures.
  This is a cooperative execution budget, not a hard-real-time or OS sandbox
  guarantee; the consumer owns process-tree and resource isolation.
  """

  @behaviour Wotex.Conformance.Target

  alias Wotex.Conformance.{Canonical, Error, Input, Target.Response, Value}

  @archive_placeholder "{subject_archive}"
  @default_timeout_ms 5_000
  @default_max_output_bytes 1_048_576
  @max_args 64
  @max_arg_bytes 4_096
  @max_env 64
  @max_env_bytes 1_024
  @env_key ~r/^[A-Za-z_][A-Za-z0-9_]*$/
  @sensitive_env ~r/(^|_)(PASSWORD|PASSWD|SECRET|TOKEN|CREDENTIAL|API_?KEY|PRIVATE_?KEY)($|_)/u

  @enforce_keys [
    :executable,
    :args,
    :artifact_path,
    :environment,
    :timeout_ms,
    :max_output_bytes
  ]
  defstruct [:executable, :args, :artifact_path, :environment, :timeout_ms, :max_output_bytes]

  @type t :: %__MODULE__{
          executable: Path.t(),
          args: [String.t()],
          artifact_path: Path.t(),
          environment: %{String.t() => String.t()},
          timeout_ms: pos_integer(),
          max_output_bytes: pos_integer()
        }

  @doc """
  Configures an isolated executable target from decoded data.

  The executable and archive paths must be absolute. Arguments may use
  `{subject_archive}` exactly once where the archive path should be inserted.
  """
  @spec new(map()) :: {:ok, t()} | {:error, Error.t()}
  def new(input) when is_map(input) do
    with :ok <-
           Input.only_keys(
             input,
             ~w(executable args artifact_path environment timeout_ms max_output_bytes)
           ),
         {:ok, executable_input} <- Input.required(input, :executable),
         {:ok, executable} <- validate_executable(executable_input),
         {:ok, args_input} <- Input.required(input, :args),
         {:ok, args} <- validate_args(args_input),
         {:ok, artifact_path_input} <- Input.required(input, :artifact_path),
         {:ok, artifact_path} <- validate_artifact_path(artifact_path_input),
         {:ok, environment} <- validate_environment(Input.optional(input, :environment, %{})),
         {:ok, timeout_ms} <-
           validate_positive_limit(
             Input.optional(input, :timeout_ms, @default_timeout_ms),
             "timeout_ms"
           ),
         {:ok, max_output_bytes} <-
           validate_positive_limit(
             Input.optional(input, :max_output_bytes, @default_max_output_bytes),
             "max_output_bytes"
           ) do
      {:ok,
       %__MODULE__{
         executable: executable,
         args: args,
         artifact_path: artifact_path,
         environment: environment,
         timeout_ms: timeout_ms,
         max_output_bytes: max_output_bytes
       }}
    end
  end

  def new(_input), do: {:error, Error.new(:invalid_type, "external target must be an object")}

  @impl Wotex.Conformance.Target
  def artifact_path(%__MODULE__{artifact_path: artifact_path}), do: {:ok, artifact_path}

  @impl Wotex.Conformance.Target
  def invoke(%__MODULE__{} = target, request) do
    started = System.monotonic_time()
    deadline = System.convert_time_unit(started, :native, :millisecond) + target.timeout_ms

    result =
      with {:ok, encoded} <- Canonical.encode(request),
           {:ok, vector_id} <- request_vector_id(request),
           {:ok, output} <- exchange(target, encoded, deadline),
           {:ok, decoded} <- decode_response(output),
           {:ok, response} <- Response.new(decoded, vector_id) do
        {:ok, response}
      end

    duration_us =
      System.monotonic_time()
      |> Kernel.-(started)
      |> System.convert_time_unit(:native, :microsecond)

    case result do
      {:ok, response} -> {:ok, response, duration_us}
      {:error, %Error{} = error} -> {:error, error, duration_us}
    end
  end

  defp validate_executable(value) when is_binary(value) do
    cond do
      Path.type(value) != :absolute ->
        {:error, Error.new(:invalid_executable, "target executable path must be absolute")}

      byte_size(value) > @max_arg_bytes ->
        {:error, Error.new(:limit_exceeded, "target executable path exceeds its byte limit")}

      true ->
        case File.stat(value) do
          {:ok, %File.Stat{type: :regular}} ->
            {:ok, value}

          _result ->
            {:error, Error.new(:invalid_executable, "target executable must be a regular file")}
        end
    end
  end

  defp validate_executable(_value),
    do: {:error, Error.new(:invalid_executable, "target executable must be a string")}

  defp validate_args(args) when is_list(args) and length(args) <= @max_args do
    args
    |> Enum.reduce_while({:ok, []}, fn arg, {:ok, valid} ->
      cond do
        not is_binary(arg) ->
          {:halt, {:error, Error.new(:invalid_argument, "target arguments must be strings")}}

        not String.valid?(arg) or byte_size(arg) > @max_arg_bytes ->
          {:halt,
           {:error,
            Error.new(:invalid_argument, "target argument exceeds its encoding or byte limit")}}

        String.contains?(arg, @archive_placeholder) and arg != @archive_placeholder ->
          {:halt,
           {:error,
            Error.new(:invalid_argument, "archive placeholder must occupy one complete argument")}}

        true ->
          {:cont, {:ok, [arg | valid]}}
      end
    end)
    |> then(fn
      {:ok, valid} ->
        valid = Enum.reverse(valid)

        if Enum.count(valid, &(&1 == @archive_placeholder)) == 1 do
          {:ok, valid}
        else
          {:error,
           Error.new(:invalid_argument, "target arguments require exactly one archive placeholder")}
        end

      {:error, error} ->
        {:error, error}
    end)
  end

  defp validate_args(_args),
    do: {:error, Error.new(:invalid_argument, "target arguments must be a bounded list")}

  defp validate_artifact_path(path) when is_binary(path) and path != "" do
    if Path.type(path) == :absolute and byte_size(path) <= @max_arg_bytes do
      {:ok, path}
    else
      {:error, Error.new(:invalid_artifact_path, "artifact path must be an absolute bounded path")}
    end
  end

  defp validate_artifact_path(_path),
    do: {:error, Error.new(:invalid_artifact_path, "artifact path must be a string")}

  defp validate_environment(environment)
       when is_map(environment) and map_size(environment) <= @max_env do
    environment
    |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, valid} ->
      cond do
        not is_binary(key) or not is_binary(value) ->
          {:halt,
           {:error,
            Error.new(:invalid_environment, "target environment keys and values must be strings")}}

        not Regex.match?(@env_key, key) or Regex.match?(@sensitive_env, String.upcase(key)) ->
          {:halt,
           {:error, Error.new(:invalid_environment, "target environment key is not allowed")}}

        not String.valid?(value) or byte_size(value) > @max_env_bytes or
            String.contains?(value, <<0>>) ->
          {:halt,
           {:error,
            Error.new(
              :invalid_environment,
              "target environment value exceeds its encoding or byte limit"
            )}}

        true ->
          {:cont, {:ok, Map.put(valid, key, value)}}
      end
    end)
  end

  defp validate_environment(_environment) do
    {:error, Error.new(:invalid_environment, "target environment must be a bounded object")}
  end

  defp validate_positive_limit(value, _field) when is_integer(value) and value > 0, do: {:ok, value}

  defp validate_positive_limit(_value, field) do
    {:error, Error.new(:invalid_limit, "#{field} must be a positive integer")}
  end

  defp open(target) do
    args =
      Enum.map(target.args, fn argument ->
        argument
        |> then(&if(&1 == @archive_placeholder, do: target.artifact_path, else: &1))
        |> String.to_charlist()
      end)

    environment = scrubbed_environment(target.environment)

    options = [
      :binary,
      :exit_status,
      :hide,
      :stderr_to_stdout,
      :use_stdio,
      {:args, args},
      {:env, environment}
    ]

    try do
      {:ok, Port.open({:spawn_executable, String.to_charlist(target.executable)}, options)}
    rescue
      ArgumentError ->
        {:error, Error.new(:target_start_failed, "external target could not be started")}
    catch
      :error, _reason ->
        {:error, Error.new(:target_start_failed, "external target could not be started")}
    end
  end

  defp scrubbed_environment(environment) do
    unset = System.get_env() |> Map.keys() |> Enum.map(&{String.to_charlist(&1), false})

    supplied =
      Enum.map(environment, fn {key, value} ->
        {String.to_charlist(key), String.to_charlist(value)}
      end)

    unset ++ supplied
  end

  defp exchange(target, encoded, deadline) do
    with :ok <- within_deadline(deadline),
         {:ok, port} <- open(target) do
      try do
        with :ok <- within_deadline(deadline),
             :ok <- send_request(port, encoded) do
          collect(port, deadline, target.max_output_bytes, [], 0)
        end
      after
        safe_close(port)
      end
    end
  end

  defp send_request(port, encoded) do
    case Port.command(port, [encoded, "\n"], [:nosuspend]) do
      true -> :ok
      false -> {:error, Error.new(:target_write_failed, "target request could not be written")}
    end
  rescue
    ArgumentError ->
      {:error, Error.new(:target_write_failed, "target request could not be written")}
  end

  defp collect(port, deadline, max_output_bytes, chunks, size) do
    with :ok <- within_deadline(deadline) do
      receive_output(port, deadline, max_output_bytes, chunks, size)
    end
  end

  defp receive_output(port, deadline, max_output_bytes, chunks, size) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, bytes}} ->
        next_size = size + byte_size(bytes)

        if next_size > max_output_bytes do
          {:error, Error.new(:target_output_limit, "target response exceeds its byte limit")}
        else
          collect(port, deadline, max_output_bytes, [bytes | chunks], next_size)
        end

      {^port, {:exit_status, 0}} ->
        {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}

      {^port, {:exit_status, _status}} ->
        {:error, Error.new(:target_exit_nonzero, "external target exited unsuccessfully")}
    after
      remaining ->
        {:error, Error.new(:target_timeout, "external target exceeded its time limit")}
    end
  end

  defp within_deadline(deadline) do
    if System.monotonic_time(:millisecond) < deadline do
      :ok
    else
      {:error, Error.new(:target_timeout, "external target exceeded its time limit")}
    end
  end

  defp safe_close(port) do
    Port.close(port)
  rescue
    ArgumentError -> :ok
  end

  defp decode_response(output) do
    case Jason.decode(output) do
      {:ok, response} ->
        {:ok, response}

      {:error, _reason} ->
        {:error, Error.new(:invalid_target_json, "target response is not valid JSON")}
    end
  end

  defp request_vector_id(%{"vector" => %{"id" => vector_id}}) do
    Value.validate_identifier(vector_id, "vector_id")
  end

  defp request_vector_id(_request) do
    {:error, Error.new(:invalid_target_request, "target request has no vector ID")}
  end
end
