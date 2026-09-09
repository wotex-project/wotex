defmodule Wotex.OPCUA.Native.Command do
  @moduledoc """
  Runs one explicit build command through the owned POSIX process guardian.

  `run/2` accepts an absolute guardian executable and a validated recipe step.
  Executable, arguments, environment and working directory remain separate
  values. The child environment contains only explicit recipe values; inherited
  variables are cleared before spawn. The guardian owns the child process group,
  enforces time/output limits even while the BEAM caller is suspended, and closes descendants on owner EOF.
  The caller's exit closes its Port; a successful child cannot leave background
  members of the owned group running. The caller reserves a separate 500 ms
  for guardian startup and final status delivery; the native command and cleanup
  deadlines keep their explicit recipe limits. A nil status records unverified
  native completion when the caller's total wait expires.

  Returned output is bounded build evidence, not an OPC UA result or diagnostic
  payload. This boundary covers ordinary compiler/build descendants that remain
  in their owned process group. It does not contain deliberate process-group
  escapes. Guardian compilation and workspace/tool digest verification belong
  to the explicit build owner and precede this function.
  """

  @fields ~w(id executable args cwd env timeout_ms output_bytes cleanup_ms)a
  @codes %{
    124 => :command_deadline,
    125 => :command_output_limit,
    126 => :command_setup_failed,
    127 => :command_owner_lost,
    128 => :command_terminated,
    129 => :command_cleanup_failed
  }

  @typedoc "Bounded output and the observed guardian status; nil means no final status was received."
  @type result :: %{output: binary(), exit_status: non_neg_integer() | nil}

  @doc "Executes a finite recipe step and retains its bounded output on success or failure."
  @spec run(term(), term()) :: {:ok, result()} | {:error, atom(), result()}
  def run(guardian, step) when is_binary(guardian) and is_map(step) do
    if absolute?(guardian) and valid_step?(step) do
      execute(guardian, step)
    else
      failure(:invalid_command, <<>>, nil)
    end
  rescue
    ArgumentError -> failure(:invalid_command, <<>>, nil)
  end

  def run(_, _), do: failure(:invalid_command, <<>>, nil)

  defp valid_step?(step) do
    MapSet.new(Map.keys(step)) == MapSet.new(@fields) and is_atom(step.id) and
      absolute?(step.executable) and absolute?(step.cwd) and arguments?(step.args) and
      environment?(step.env) and integer?(step.timeout_ms, 600_000) and
      integer?(step.output_bytes, 16_777_216) and integer?(step.cleanup_ms, 5000)
  end

  defp absolute?(path) when is_binary(path) do
    byte_size(path) in 1..4096 and String.valid?(path) and Path.type(path) == :absolute and
      not String.contains?(path, <<0>>)
  end

  defp absolute?(_), do: false

  defp arguments?(args) when is_list(args) do
    length(args) <= 256 and Enum.all?(args, &argument?/1) and
      Enum.reduce(args, 0, &(byte_size(&1) + &2)) <= 65_536
  end

  defp arguments?(_), do: false

  defp argument?(arg) when is_binary(arg),
    do: byte_size(arg) <= 8192 and String.valid?(arg) and not String.contains?(arg, <<0>>)

  defp argument?(_), do: false

  defp environment?(entries) when is_list(entries) do
    length(entries) <= 64 and Enum.all?(entries, &environment_entry?/1) and
      length(Enum.uniq_by(entries, &elem(&1, 0))) == length(entries)
  end

  defp environment?(_), do: false

  defp environment_entry?({key, value}) when is_binary(key) do
    byte_size(key) <= 128 and Regex.match?(~r/\A[A-Z][A-Z0-9_]*\z/, key) and
      (is_nil(value) or argument?(value))
  end

  defp environment_entry?(_), do: false

  defp integer?(value, maximum), do: is_integer(value) and value >= 1 and value <= maximum

  defp execute(guardian, step) do
    args =
      Enum.map([step.timeout_ms, step.output_bytes, step.cleanup_ms], &Integer.to_string/1) ++
        [step.cwd, step.executable | step.args]

    environment = Map.new(System.get_env(), fn {key, _} -> {key, nil} end)

    env =
      environment
      |> Map.merge(Map.new(step.env))
      |> Enum.map(fn {key, value} ->
        {String.to_charlist(key), if(is_nil(value), do: false, else: String.to_charlist(value))}
      end)

    port = Port.open({:spawn_executable, guardian}, [:binary, :exit_status, args: args, env: env])
    deadline = System.monotonic_time(:millisecond) + step.timeout_ms + step.cleanup_ms + 500

    try do
      collect(port, [], 0, step.output_bytes, deadline)
    after
      if Port.info(port), do: Port.close(port)
    end
  rescue
    _ in [ArgumentError, ErlangError] -> failure(:command_setup_failed, <<>>, nil)
  end

  defp collect(port, chunks, size, limit, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0 do
      receive do
        {^port, {:data, bytes}} when byte_size(bytes) + size <= limit ->
          collect(port, [bytes | chunks], size + byte_size(bytes), limit, deadline)

        {^port, {:data, _}} ->
          failure(:command_output_limit, output(chunks), nil)

        {^port, {:exit_status, status}} ->
          finish(status, output(chunks))
      after
        remaining -> failure(:command_deadline, output(chunks), nil)
      end
    else
      failure(:command_deadline, output(chunks), nil)
    end
  end

  defp output(chunks) do
    chunks
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp finish(0, bytes), do: {:ok, %{output: bytes, exit_status: 0}}
  defp finish(code, bytes), do: failure(Map.get(@codes, code, :command_failed), bytes, code)
  defp failure(code, bytes, status), do: {:error, code, %{output: bytes, exit_status: status}}
end
