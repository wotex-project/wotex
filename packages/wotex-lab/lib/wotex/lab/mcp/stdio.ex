defmodule Wotex.Lab.MCP.Stdio do
  @moduledoc """
  The pinned MCP stdio transport: newline-delimited JSON-RPC on standard
  input and output.

  `run/3` reads one line at a time from the input device up to
  `:max_line_bytes` (1 MiB), decodes it with the core's bounded JSON
  admission, hands it to `Wotex.Lab.MCP.Server.handle/2` and writes the reply
  as one line. Oversized or undecodable lines answer with a JSON-RPC parse
  error and the session continues; end of input ends the loop and returns the
  final state. Nothing but protocol messages is written to the output device;
  diagnostics go to standard error. `main/1` is the process entry a host or
  an assistant launcher runs with `mix run --no-halt`-free semantics: it
  builds a read-only session over no instance unless the host supplies one.
  """

  alias Wotex.Lab.MCP.Server

  @max_line_bytes 1_048_576

  @doc "Runs the loop over the given devices; returns the final session state."
  @spec run(Server.t(), IO.device(), IO.device(), keyword()) :: Server.t()
  def run(state, input, output, opts \\ []) do
    max_line = Keyword.get(opts, :max_line_bytes, @max_line_bytes)

    case IO.binread(input, :line) do
      :eof ->
        state

      {:error, _reason} ->
        state

      line when is_binary(line) ->
        state = step(state, line, output, max_line)
        run(state, input, output, opts)
    end
  end

  @doc "Handles one raw line."
  @spec step(Server.t(), binary(), IO.device(), pos_integer()) :: Server.t()
  def step(state, line, output, max_line) do
    trimmed = String.trim_trailing(line, "\n")

    cond do
      trimmed == "" ->
        state

      byte_size(trimmed) > max_line ->
        write(output, parse_error("line exceeds #{max_line} bytes"))
        state

      true ->
        dispatch(state, trimmed, output, max_line)
    end
  end

  defp dispatch(state, trimmed, output, max_line) do
    case Wotex.JSON.decode(trimmed, max_bytes: max_line) do
      {:ok, message} ->
        {reply, state} = Server.handle(state, message)
        if reply, do: write(output, reply)
        state

      {:error, _error} ->
        write(output, parse_error("line is not a JSON object"))
        state
    end
  end

  @doc "Process entry: a read-only session over standard input and output."
  @spec main([String.t()]) :: :ok
  def main(_args) do
    {:ok, state} = Server.new()
    run(state, :stdio, :stdio)
    :ok
  end

  defp write(output, reply) do
    {:ok, json} = Wotex.JSON.encode(reply)
    IO.binwrite(output, json <> "\n")
  end

  defp parse_error(message),
    do: %{"jsonrpc" => "2.0", "id" => nil, "error" => %{"code" => -32_700, "message" => message}}
end
