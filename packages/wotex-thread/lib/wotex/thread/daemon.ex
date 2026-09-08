defmodule Wotex.Thread.Daemon do
  @moduledoc "Real read-only ot-daemon Unix-socket client; never starts a daemon or changes a dataset."
  @behaviour Wotex.Thread.Client
  alias Wotex.Thread.Error
  @commands %{state: "state", version: "version", network_name: "networkname", rloc16: "rloc16"}
  @max_response 8192

  @impl Wotex.Thread.Client
  def connect(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: connect_options(opts), else: invalid_options()
  end

  def connect(_), do: invalid_options()

  defp connect_options(opts) do
    path = Keyword.get(opts, :socket_path)
    timeout = Keyword.get(opts, :timeout, 5000)
    keys = Keyword.keys(opts)

    if keys -- [:socket_path, :timeout] == [] and length(keys) == MapSet.size(MapSet.new(keys)) and
         is_binary(path) and byte_size(path) in 1..100 and not String.contains?(path, <<0>>) and
         is_integer(timeout) and timeout in 1..60_000 do
      options = [:binary, active: false, packet: :line, packet_size: @max_response]

      case :gen_tcp.connect({:local, path}, 0, options, timeout) do
        {:ok, socket} -> {:ok, %{socket: socket, owner: self()}}
        {:error, _} -> {:error, Error.new(:connect_failed)}
      end
    else
      invalid_options()
    end
  end

  @impl Wotex.Thread.Client
  def request(%{socket: socket, owner: owner}, %{type: type}, timeout)
      when owner == self() and is_integer(timeout) and timeout in 1..60_000 do
    with {:ok, command} <- Map.fetch(@commands, type),
         :ok <- :gen_tcp.send(socket, command <> "\n") do
      collect(socket, <<>>, System.monotonic_time(:millisecond) + timeout)
    else
      _ -> {:error, Error.new(:invalid_request)}
    end
  end

  def request(%{owner: owner}, _, _) when owner != self(), do: {:error, Error.new(:wrong_owner)}
  def request(_, _, _), do: {:error, Error.new(:invalid_request)}

  @impl Wotex.Thread.Client
  def disconnect(%{socket: socket, owner: owner}) when owner == self(), do: :gen_tcp.close(socket)
  def disconnect(%{owner: owner}) when owner != self(), do: {:error, Error.new(:wrong_owner)}
  def disconnect(_), do: {:error, Error.new(:invalid_options)}

  @doc "Parses bounded daemon output; Error responses never count as Done."
  @spec parse(term()) :: {:ok, String.t()} | :more | {:error, Error.t()}
  def parse(bytes) when is_binary(bytes) and byte_size(bytes) <= @max_response do
    cond do
      match?({:incomplete, _, _}, :unicode.characters_to_binary(bytes, :utf8, :utf8)) ->
        :more

      not String.valid?(bytes) ->
        {:error, Error.new(:invalid_response)}

      Regex.match?(~r/(?:^|\n)(?:> )?Error [0-9]+:/, bytes) ->
        {:error, Error.new(:remote_error)}

      Regex.match?(~r/(?:^|\n)Done\r?\n/, bytes) ->
        [value, _] = Regex.split(~r/(?:^|\n)Done\r?\n/, bytes, parts: 2)
        {:ok, String.trim_leading(String.trim(value), "> ")}

      true ->
        :more
    end
  end

  def parse(_), do: {:error, Error.new(:response_limit)}

  defp collect(socket, bytes, deadline) do
    case parse(bytes) do
      :more ->
        remaining = deadline - System.monotonic_time(:millisecond)
        result = if remaining > 0, do: :gen_tcp.recv(socket, 0, remaining), else: {:error, :timeout}

        case result do
          {:ok, data} ->
            collect(socket, bytes <> data, deadline)

          {:error, :timeout} ->
            :gen_tcp.close(socket)
            {:error, Error.new(:timeout)}

          {:error, :emsgsize} ->
            :gen_tcp.close(socket)
            {:error, Error.new(:response_limit)}

          {:error, :closed} ->
            {:error, Error.new(:transport_closed)}

          {:error, _} ->
            :gen_tcp.close(socket)
            {:error, Error.new(:invalid_response)}
        end

      {:error, _} = error ->
        :gen_tcp.close(socket)
        error

      result ->
        result
    end
  end

  defp invalid_options, do: {:error, Error.new(:invalid_options)}
end
