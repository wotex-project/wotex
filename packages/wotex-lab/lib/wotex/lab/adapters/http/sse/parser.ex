# Compiled only when the optional package behind this seam is present;
# the base package stays usable without it.
if Code.ensure_loaded?(Wotex.Binding.HTTP.Client) do
  defmodule Wotex.Lab.Adapters.HTTP.SSE.Parser do
    @moduledoc """
    Incremental, bounded Server-Sent Events parser.

    Feed it arbitrary byte chunks: it handles UTF-8 sequences split across
    chunks, `LF`, `CRLF` and `CR` line endings, comment lines, multi-line `data`
    fields joined with `LF`, `event`, `id` (ignored when it contains a NUL) and
    `retry` (digits only), and dispatches one `Wotex.Binding.HTTP.SSE.Event` per
    blank line. A line longer than `max_line_bytes` or a pending event whose data
    exceeds `max_event_bytes` fails with a typed error instead of growing. It
    keeps no process state; the session owns the parser state.
    """

    alias Wotex.Binding.HTTP.SSE.Event
    alias Wotex.Lab.Error

    @type t :: %__MODULE__{
            buffer: binary(),
            data: [binary()],
            event: String.t() | nil,
            id: String.t() | nil,
            retry: non_neg_integer() | nil,
            max_line_bytes: pos_integer(),
            max_event_bytes: pos_integer()
          }

    defstruct buffer: "",
              data: [],
              event: nil,
              id: nil,
              retry: nil,
              max_line_bytes: 65_536,
              max_event_bytes: 262_144

    @doc "Builds parser state with explicit line and event byte bounds."
    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      %__MODULE__{
        max_line_bytes: Keyword.get(opts, :max_line_bytes, 65_536),
        max_event_bytes: Keyword.get(opts, :max_event_bytes, 262_144)
      }
    end

    @doc "Consumes a chunk and returns dispatched events with the updated state."
    @spec feed(t(), binary()) :: {:ok, [Event.t()], t()} | {:error, Error.t()}
    def feed(%__MODULE__{} = state, chunk) when is_binary(chunk) do
      buffer = state.buffer <> chunk

      if byte_size(buffer) > state.max_line_bytes and not String.contains?(buffer, ["\n", "\r"]) do
        {:error,
         Error.new(:sse_line_too_long, :transport, "SSE line exceeds the byte bound",
           class: :protocol
         )}
      else
        lines(%{state | buffer: buffer}, [])
      end
    end

    defp lines(state, events) do
      case split_line(state.buffer) do
        {:line, line, rest} -> consume(%{state | buffer: rest}, line, events)
        :incomplete -> {:ok, Enum.reverse(events), state}
      end
    end

    defp consume(state, line, _) when byte_size(line) > state.max_line_bytes do
      {:error,
       Error.new(:sse_line_too_long, :transport, "SSE line exceeds the byte bound",
         class: :protocol
       )}
    end

    defp consume(state, line, events) do
      case handle_line(state, line) do
        {:ok, nil, next} -> lines(next, events)
        {:ok, event, next} -> lines(next, [event | events])
        {:error, error} -> {:error, error}
      end
    end

    # A trailing CR may be the first half of CRLF; wait for more bytes.
    defp split_line(buffer) do
      case :binary.match(buffer, ["\r\n", "\n", "\r"]) do
        {position, 2} ->
          {:line, binary_part(buffer, 0, position),
           binary_part(buffer, position + 2, byte_size(buffer) - position - 2)}

        {position, 1} ->
          terminator = binary_part(buffer, position, 1)

          if terminator == "\r" and position + 1 == byte_size(buffer) do
            :incomplete
          else
            {:line, binary_part(buffer, 0, position),
             binary_part(buffer, position + 1, byte_size(buffer) - position - 1)}
          end

        :nomatch ->
          :incomplete
      end
    end

    defp handle_line(state, ""), do: dispatch(state)
    defp handle_line(state, ":" <> _), do: {:ok, nil, state}

    defp handle_line(state, line) do
      {field, value} =
        case :binary.match(line, ":") do
          {position, 1} ->
            value = binary_part(line, position + 1, byte_size(line) - position - 1)
            {binary_part(line, 0, position), String.replace_prefix(value, " ", "")}

          :nomatch ->
            {line, ""}
        end

      field(state, field, value)
    end

    defp field(state, "data", value) do
      total = Enum.reduce(state.data, byte_size(value), &(byte_size(&1) + &2)) + length(state.data)

      if total > state.max_event_bytes do
        {:error,
         Error.new(:sse_event_too_large, :transport, "SSE event data exceeds the byte bound",
           class: :protocol
         )}
      else
        {:ok, nil, %{state | data: [value | state.data]}}
      end
    end

    defp field(state, "event", value), do: {:ok, nil, %{state | event: value}}

    defp field(state, "id", value) do
      if String.contains?(value, <<0>>),
        do: {:ok, nil, state},
        else: {:ok, nil, %{state | id: value}}
    end

    defp field(state, "retry", value) do
      case Integer.parse(value) do
        {retry, ""} when retry >= 0 -> {:ok, nil, %{state | retry: retry}}
        _ -> {:ok, nil, state}
      end
    end

    defp field(state, _, _), do: {:ok, nil, state}

    defp dispatch(%{data: []} = state), do: {:ok, nil, reset(state)}

    defp dispatch(state) do
      data =
        state.data
        |> Enum.reverse()
        |> Enum.join("\n")

      if String.valid?(data) do
        case Event.new(data, event: blank_to_nil(state.event), id: state.id, retry: state.retry) do
          {:ok, event} ->
            {:ok, event, reset(state)}

          {:error, _} ->
            {:error,
             Error.new(:sse_event_invalid, :transport, "SSE event is invalid", class: :protocol)}
        end
      else
        {:error,
         Error.new(:sse_event_invalid, :transport, "SSE event data is not valid UTF-8",
           class: :protocol
         )}
      end
    end

    defp reset(state), do: %{state | data: [], event: nil, retry: nil}

    defp blank_to_nil(""), do: nil
    defp blank_to_nil(value), do: value
  end
end
