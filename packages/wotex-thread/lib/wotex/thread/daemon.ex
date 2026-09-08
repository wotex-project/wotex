defmodule Wotex.Thread.Daemon do
  @moduledoc "Real read-only ot-daemon Unix-socket client; never starts a daemon or changes a dataset."
  @behaviour Wotex.Thread.Client
  alias Wotex.Thread.{Address, Error}
  @commands %{state: "state", version: "version", network_name: "networkname", rloc16: "rloc16"}
  @max_response 8192

  @impl Wotex.Thread.Client
  def connect(opts) when is_list(opts) do
    if bounded_options?(opts, 0), do: connect_options(opts), else: invalid_options()
  end

  def connect(_), do: invalid_options()

  defp connect_options(opts) do
    path = Keyword.get(opts, :socket_path)
    timeout = Keyword.get(opts, :timeout, 5000)
    keys = Keyword.keys(opts)

    if keys -- [:socket_path, :timeout] == [] and length(keys) == MapSet.size(MapSet.new(keys)) and
         is_binary(path) and byte_size(path) in 1..100 and not String.contains?(path, <<0>>) and
         is_integer(timeout) and timeout in 1..60_000 do
      options = [
        :binary,
        active: false,
        packet: :line,
        packet_size: @max_response,
        send_timeout: timeout,
        send_timeout_close: true
      ]

      case :gen_tcp.connect({:local, path}, 0, options, timeout) do
        {:ok, socket} -> {:ok, %{socket: socket, owner: self()}}
        {:error, _} -> {:error, Error.new(:connect_failed)}
      end
    else
      invalid_options()
    end
  end

  @impl Wotex.Thread.Client
  def request(%{socket: socket, owner: owner} = handle, message, timeout)
      when owner == self() and map_size(handle) == 2 and is_port(socket) and
             is_integer(timeout) and timeout in 1..60_000 do
    deadline = System.monotonic_time(:millisecond) + timeout

    with :ok <- Address.validate_message(message),
         :ok <- owned_socket(socket),
         :ok <- idle_socket(socket),
         :ok <- send_budget(socket, deadline),
         :ok <- :gen_tcp.send(socket, Map.fetch!(@commands, message.type) <> "\n") do
      collect(socket, <<>>, message.type, deadline)
    else
      {:error, %Error{}} = error -> error
      {:error, :timeout} -> close_error(socket, :timeout)
      _ -> close_error(socket, :transport_closed)
    end
  end

  def request(%{owner: owner}, _, _) when owner != self(), do: {:error, Error.new(:wrong_owner)}
  def request(_, _, _), do: {:error, Error.new(:invalid_request)}

  @impl Wotex.Thread.Client
  def disconnect(%{socket: socket, owner: owner} = handle)
      when owner == self() and map_size(handle) == 2 and is_port(socket) do
    case owned_socket(socket) do
      :ok -> :gen_tcp.close(socket)
      {:error, %Error{code: :transport_closed}} -> :ok
      error -> error
    end
  end

  def disconnect(%{owner: owner}) when owner != self(), do: {:error, Error.new(:wrong_owner)}
  def disconnect(_), do: {:error, Error.new(:invalid_options)}

  @doc "Parses bounded daemon output; Error responses never count as Done."
  @spec parse(term()) :: {:ok, String.t()} | :more | {:error, Error.t()}
  def parse(bytes), do: parse_frame(bytes, :generic)

  @doc """
  Parses a response to one read command, removing its optional echo.

  State, version and network name results are validated strings. RLOC16 results
  are unsigned 16-bit integers; the OpenThread invalid address `ffff` becomes
  `nil`. Missing completion returns `:more`. Invalid or additional output
  returns a structured error without including the received text.
  """
  @spec parse(term(), :state | :version | :network_name | :rloc16) ::
          {:ok, String.t() | non_neg_integer() | nil} | :more | {:error, Error.t()}
  def parse(bytes, type) when is_map_key(@commands, type), do: parse_frame(bytes, type)
  def parse(_, _), do: {:error, Error.new(:invalid_request)}

  defp parse_frame(bytes, type) when is_binary(bytes) and byte_size(bytes) <= @max_response do
    case :unicode.characters_to_binary(bytes, :utf8, :utf8) do
      {:incomplete, _, _} -> :more
      {:error, _, _} -> {:error, Error.new(:invalid_response)}
      _ -> parse_lines(bytes, type)
    end
  end

  defp parse_frame(_, _), do: {:error, Error.new(:response_limit)}

  defp parse_lines(bytes, type) do
    lines =
      bytes
      |> strip_prompt()
      |> String.split("\n")
      |> Enum.map(&trim_cr/1)

    case Enum.reverse(lines) do
      [tail, "Done" | before] when tail in ["", "> "] ->
        result_lines(Enum.reverse(before), type)

      ["Done" | _] ->
        :more

      _ ->
        cond do
          Enum.any?(lines, &remote_error?/1) ->
            {:error, Error.new(:remote_error)}

          "Done" in lines and type not in [:network_name, :version] ->
            {:error, Error.new(:invalid_response)}

          true ->
            :more
        end
    end
  end

  defp trim_cr(line) do
    if String.ends_with?(line, "\r"),
      do: binary_part(line, 0, byte_size(line) - 1),
      else: line
  end

  defp result_lines(lines, type) do
    if Enum.any?(lines, &remote_error?/1) do
      {:error, Error.new(:remote_error)}
    else
      case remove_echo(lines, type) do
        [] when type == :generic -> {:ok, ""}
        [value] -> typed_value(value, type)
        _ -> {:error, Error.new(:invalid_response)}
      end
    end
  end

  defp remove_echo([command, value], type) when is_map_key(@commands, type) do
    if command == Map.fetch!(@commands, type), do: [strip_prompt(value)], else: [command, value]
  end

  defp remove_echo(lines, _), do: lines

  defp typed_value(value, :generic), do: {:ok, value}

  defp typed_value(value, :state)
       when value in ["disabled", "detached", "child", "router", "leader"],
       do: {:ok, value}

  defp typed_value(value, :rloc16) do
    if Regex.match?(~r/\A[0-9a-f]{4}\z/, value) do
      {locator, ""} = Integer.parse(value, 16)
      {:ok, if(locator == 0xFFFF, do: nil, else: locator)}
    else
      {:error, Error.new(:invalid_response)}
    end
  end

  defp typed_value(value, type) when type in [:version, :network_name] do
    limit = if type == :network_name, do: 16, else: 1024

    if byte_size(value) in 1..limit and not Regex.match?(~r/[\x00-\x1f\x7f]/, value),
      do: {:ok, value},
      else: {:error, Error.new(:invalid_response)}
  end

  defp typed_value(_, _), do: {:error, Error.new(:invalid_response)}
  defp remote_error?(line), do: Regex.match?(~r/\A(?:> )?Error [0-9]+:/, line)
  defp strip_prompt("> " <> bytes), do: bytes
  defp strip_prompt(bytes), do: bytes

  defp collect(socket, bytes, type, deadline) do
    case parse(bytes, type) do
      :more -> receive_more(socket, bytes, type, deadline)
      {:error, %Error{code: code}} -> close_error(socket, code)
      {:ok, _} = result -> completed(socket, bytes, result)
    end
  end

  defp receive_more(socket, bytes, type, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    result = if remaining > 0, do: :gen_tcp.recv(socket, 0, remaining), else: {:error, :timeout}

    case result do
      {:ok, data} when byte_size(bytes) + byte_size(data) <= @max_response ->
        collect(socket, bytes <> data, type, deadline)

      {:ok, _} ->
        close_error(socket, :response_limit)

      {:error, :timeout} ->
        close_error(socket, :timeout)

      {:error, :emsgsize} ->
        close_error(socket, :response_limit)

      {:error, :closed} ->
        close_error(socket, :transport_closed)

      {:error, _} ->
        close_error(socket, :invalid_response)
    end
  end

  defp completed(socket, bytes, result) do
    case :gen_tcp.recv(socket, 0, 0) do
      {:error, :timeout} ->
        result

      {:error, :closed} ->
        result

      {:ok, tail} when byte_size(bytes) + byte_size(tail) <= @max_response ->
        close_error(socket, :invalid_response)

      _ ->
        close_error(socket, :response_limit)
    end
  end

  defp send_budget(socket, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0,
      do: :inet.setopts(socket, send_timeout: remaining),
      else: close_error(socket, :timeout)
  end

  defp idle_socket(socket) do
    case :gen_tcp.recv(socket, 0, 0) do
      {:error, :timeout} -> :ok
      {:error, :closed} -> close_error(socket, :transport_closed)
      _ -> close_error(socket, :invalid_response)
    end
  end

  defp owned_socket(socket) do
    case :erlang.port_info(socket, :connected) do
      {:connected, owner} when owner == self() -> socket_options(socket)
      {:connected, _} -> {:error, Error.new(:wrong_owner)}
      :undefined -> {:error, Error.new(:transport_closed)}
    end
  end

  defp socket_options(socket) do
    case :inet.getopts(socket, [:active, :packet]) do
      {:ok, [active: false, packet: :line]} -> :ok
      _ -> {:error, Error.new(:invalid_request)}
    end
  end

  defp close_error(socket, code) do
    :gen_tcp.close(socket)
    {:error, Error.new(code)}
  end

  defp bounded_options?([], _), do: true

  defp bounded_options?([{key, _} | tail], count) when is_atom(key) and count < 2,
    do: bounded_options?(tail, count + 1)

  defp bounded_options?(_, _), do: false

  defp invalid_options, do: {:error, Error.new(:invalid_options)}
end
