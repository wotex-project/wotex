# Compiled only when the optional package behind this seam is present;
# the base package stays usable without it.
if Code.ensure_loaded?(Wotex.Binding.HTTP.Client) do
  defmodule Wotex.Lab.Adapters.HTTP.SSE.Session do
    @moduledoc """
    A linked process that owns one streaming HTTP connection for an SSE stream.

    `open/4` runs in the runtime subscription process (the owner): it spawns the
    session linked to the owner, waits for the handshake, and returns the status
    and headers so the binding can validate them. The session issues the request
    with `Req` in asynchronous mode, feeds every chunk through the bounded
    `Wotex.Lab.Adapters.HTTP.SSE.Parser`, and sends each dispatched
    `Wotex.Binding.HTTP.SSE.Event` to the owner as `{:wotex_transport_frame, event}`.

    The credential is used to build the handshake request only and is not part
    of the loop state. When the server ends the stream or the parser rejects a
    line, the session exits with a `:shutdown` reason, which the owner reports as
    `:transport_down`; `close/1` ends the session normally after cancelling the
    response. No reconnect happens here: reconnecting is a host decision that
    re-enters runtime credential resolution.
    """

    alias Wotex.Lab.Adapters.HTTP.SSE.Parser
    alias Wotex.Lab.Telemetry

    @doc "Opens a stream and waits up to `timeout` milliseconds for the handshake."
    @spec open(keyword(), pid(), keyword(), timeout()) ::
            {:ok, pid(), non_neg_integer(), [{String.t(), String.t()}]} | {:error, term()}
    def open(request_options, owner, parser_options, timeout) when is_pid(owner) do
      parent = self()
      session = spawn_link(fn -> connect(parent, owner, request_options, parser_options) end)

      receive do
        {:sse_handshake, ^session, {:ok, status, headers}} -> {:ok, session, status, headers}
        {:sse_handshake, ^session, {:error, reason}} -> {:error, reason}
      after
        timeout ->
          Process.unlink(session)
          Process.exit(session, :kill)
          {:error, :timeout}
      end
    end

    @doc "Cancels the response and ends the session normally."
    @spec close(pid()) :: :ok
    def close(session) when is_pid(session) do
      send(session, {:close, self()})

      receive do
        {:closed, ^session} -> :ok
      after
        1_000 -> :ok
      end
    end

    defp connect(parent, owner, request_options, parser_options) do
      case Req.request(Keyword.put(request_options, :into, :self)) do
        {:ok,
         %Req.Response{status: status, headers: headers, body: %Req.Response.Async{}} =
             response} ->
          send(parent, {:sse_handshake, self(), {:ok, status, flatten(headers)}})

          if status == 200 do
            loop(response, owner, Parser.new(parser_options))
          else
            _ = Req.cancel_async_response(response)
            exit(:normal)
          end

        {:ok, %Req.Response{status: status, headers: headers}} ->
          send(parent, {:sse_handshake, self(), {:ok, status, flatten(headers)}})
          exit(:normal)

        {:error, %{reason: :timeout}} ->
          send(parent, {:sse_handshake, self(), {:error, :timeout}})
          exit(:normal)

        {:error, _} ->
          send(parent, {:sse_handshake, self(), {:error, :connect_failed}})
          exit(:normal)
      end
    end

    defp loop(response, owner, parser) do
      receive do
        {:close, from} ->
          _ = Req.cancel_async_response(response)
          send(from, {:closed, self()})
          exit(:normal)

        message ->
          case Req.parse_message(response, message) do
            {:ok, chunks} -> handle_chunks(chunks, response, owner, parser)
            :unknown -> loop(response, owner, parser)
          end
      end
    end

    defp handle_chunks([], response, owner, parser), do: loop(response, owner, parser)

    defp handle_chunks([{:data, bytes} | rest], response, owner, parser) do
      Telemetry.event(:sse, :parse, %{bytes: byte_size(bytes)}, %{profile: :http})

      case Parser.feed(parser, bytes) do
        {:ok, events, next_parser} ->
          Enum.each(events, &send(owner, {:wotex_transport_frame, &1}))
          handle_chunks(rest, response, owner, next_parser)

        {:error, error} ->
          _ = Req.cancel_async_response(response)
          exit({:shutdown, error.code})
      end
    end

    defp handle_chunks([:done | _], response, _, _) do
      _ = Req.cancel_async_response(response)
      exit({:shutdown, :stream_ended})
    end

    defp handle_chunks([_ | rest], response, owner, parser),
      do: handle_chunks(rest, response, owner, parser)

    defp flatten(headers) when is_map(headers) do
      Enum.flat_map(headers, fn {name, values} -> Enum.map(List.wrap(values), &{name, &1}) end)
    end
  end
end
