defmodule Wotex.Zigbee.ZCL.PollControl do
  @moduledoc """
  Inert finite Poll Control commands and source-checked check-in observations.

  This profile pins ZCL document 07-5123 revision 8, section 3.16, cluster
  `0x0020`. It admits Check-in, Check-in Response, Fast Poll Stop, Set Long
  Poll Interval, Set Short Poll Interval and their Default Responses. It
  neither configures bindings nor sends, polls or changes a device on load.
  Manufacturer extensions and other commands are outside this finite profile.

  Interval arguments are integer quarterseconds. The receiver owns its
  optional limits and interval relationships; consumers qualify battery
  policy and authorize every command. A response requesting fast polling or
  a successful Default Response establishes neither wakefulness nor delivery.
  """

  alias Wotex.Zigbee.{Error, Event, Routes}

  @commands %{
    0 => :checkin_response,
    1 => :fast_poll_stop,
    2 => :set_long_poll,
    3 => :set_short_poll
  }
  @event_fields Map.keys(%Event{kind: nil, subsystem: nil, id: nil, payload: nil})

  @type message :: %{
          command:
            :checkin
            | :checkin_response
            | :fast_poll_stop
            | :set_long_poll
            | :set_short_poll
            | :default_response,
          sequence: byte(),
          direction: Wotex.Zigbee.ZCL.direction(),
          disable_default_response: boolean(),
          parameters: map(),
          raw: binary()
        }
  @type observation :: %{
          peer_ieee: binary(),
          event: Event.t(),
          checkin: message(),
          response_deadline_ms: integer(),
          response_window: :open | :elapsed
        }

  @doc """
  Encodes an explicit Check-in Response, retaining zero and ignored timeout values.

  `start_fast_polling` is a boolean; timeout is 0–65,535 quarterseconds.
  Zero asks the server to use its FastPollTimeout attribute, not an infinite
  host deadline. When start is false, the server may ignore the timeout.
  Client commands permit Default Responses by clearing that header flag.
  """
  @spec checkin_response(byte(), boolean(), non_neg_integer()) ::
          {:ok, binary()} | {:error, Error.t()}
  def checkin_response(sequence, start_fast_polling, timeout_qs)
      when is_boolean(start_fast_polling) and is_integer(timeout_qs) and timeout_qs in 0..0xFFFF do
    start = if start_fast_polling, do: 1, else: 0
    encode(sequence, 0, <<start, timeout_qs::little-16>>)
  end

  def checkin_response(_, _, _), do: failure(:invalid_value)

  @doc "Encodes an explicit Fast Poll Stop; other bound clients may keep the server polling."
  @spec fast_poll_stop(byte()) :: {:ok, binary()} | {:error, Error.t()}
  def fast_poll_stop(sequence), do: encode(sequence, 1, <<>>)

  @doc "Encodes a long poll interval from 4 through `0x6E0000` quarterseconds."
  @spec set_long_poll_interval(byte(), pos_integer()) :: {:ok, binary()} | {:error, Error.t()}
  def set_long_poll_interval(sequence, interval_qs)
      when is_integer(interval_qs) and interval_qs in 4..0x6E0000,
      do: encode(sequence, 2, <<interval_qs::little-32>>)

  def set_long_poll_interval(_, _), do: failure(:invalid_value)

  @doc "Encodes a short poll interval from 1 through 65,535 quarterseconds."
  @spec set_short_poll_interval(byte(), pos_integer()) :: {:ok, binary()} | {:error, Error.t()}
  def set_short_poll_interval(sequence, interval_qs)
      when is_integer(interval_qs) and interval_qs in 1..0xFFFF,
      do: encode(sequence, 3, <<interval_qs::little-16>>)

  def set_short_poll_interval(_, _), do: failure(:invalid_value)

  @doc "Converts uint32 quarterseconds exactly to milliseconds without inferring zero's meaning."
  @spec quarterseconds_to_ms(non_neg_integer()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def quarterseconds_to_ms(value) when is_integer(value) and value in 0..0xFFFFFFFF,
    do: {:ok, value * 250}

  def quarterseconds_to_ms(_), do: failure(:invalid_value)

  @doc "Decodes only the complete finite layouts, retaining sequence, flags, parameters and bytes."
  @spec decode(binary()) :: {:ok, message()} | {:error, Error.t()}
  def decode(<<control, sequence, 0>> = raw) when control in [9, 25],
    do: decoded(raw, sequence, :server_to_client, :checkin, %{})

  def decode(<<control, sequence, 0, start, timeout::little-16>> = raw)
      when control in [1, 17] and start in [0, 1],
      do:
        decoded(raw, sequence, :client_to_server, :checkin_response, %{
          start_fast_polling: start == 1,
          timeout_qs: timeout
        })

  def decode(<<control, sequence, 1>> = raw) when control in [1, 17],
    do: decoded(raw, sequence, :client_to_server, :fast_poll_stop, %{})

  def decode(<<control, sequence, 2, interval::little-32>> = raw)
      when control in [1, 17] and interval in 4..0x6E0000,
      do: decoded(raw, sequence, :client_to_server, :set_long_poll, %{interval_qs: interval})

  def decode(<<control, sequence, 3, interval::little-16>> = raw)
      when control in [1, 17] and interval in 1..0xFFFF,
      do: decoded(raw, sequence, :client_to_server, :set_short_poll, %{interval_qs: interval})

  def decode(<<control, sequence, 11, command, status>> = raw)
      when control in [8, 24] and is_map_key(@commands, command),
      do:
        decoded(raw, sequence, :server_to_client, :default_response, %{
          original_command: Map.fetch!(@commands, command),
          status: if(status == 0, do: :success, else: {:error, status})
        })

  def decode(_), do: failure(:invalid_frame)

  @doc """
  Checks one AF Check-in source through current custody and preserves its Event.

  The response deadline is at most 7,680 ms from the owner observation and
  current custody expiry. A late observation remains visible with an elapsed
  window. An open host window is no proof the server still polls; revision 8
  permits it to return to its long interval without a response after 7.68 s.
  This function sends no response and changes no reporting or queue policy.
  """
  @spec observe_checkin(Routes.t(), Event.t(), integer()) ::
          {:ok, observation()} | {:error, Error.t()}
  def observe_checkin(routes, %Event{} = event, now) do
    with true <- complete_event?(event),
         true <-
           event.kind == :af_incoming and event.subsystem == 4 and event.id == 0x81 and
             event.cluster == 0x0020 and endpoint?(event.source_endpoint) and
             endpoint?(event.endpoint),
         {:ok, source} <- Routes.resolve(routes, event, now),
         {:ok, %{command: :checkin} = checkin} <- decode(event.payload) do
      deadline = min(event.received_at_ms + 7_680, source.entry.expires_at_ms)

      {:ok,
       %{
         peer_ieee: source.entry.peer_ieee,
         event: event,
         checkin: checkin,
         response_deadline_ms: deadline,
         response_window: if(now < deadline, do: :open, else: :elapsed)
       }}
    else
      false -> failure(:invalid_value)
      {:ok, _} -> failure(:invalid_frame)
      error -> error
    end
  end

  def observe_checkin(_, _, _), do: failure(:invalid_value)

  defp encode(sequence, command, payload) when is_integer(sequence) and sequence in 0..255,
    do: {:ok, <<1, sequence, command, payload::binary>>}

  defp encode(_, _, _), do: failure(:invalid_value)

  defp decoded(<<control, _::binary>> = raw, sequence, direction, command, parameters),
    do:
      {:ok,
       %{
         command: command,
         sequence: sequence,
         direction: direction,
         disable_default_response: Bitwise.band(control, 16) != 0,
         parameters: parameters,
         raw: raw
       }}

  defp complete_event?(event),
    do:
      map_size(event) == length(@event_fields) and
        Enum.all?(@event_fields, &Map.has_key?(event, &1))

  defp endpoint?(value), do: is_integer(value) and value in 1..240
  defp failure(kind), do: {:error, %Error{kind: kind, operation: :poll_control}}
end
