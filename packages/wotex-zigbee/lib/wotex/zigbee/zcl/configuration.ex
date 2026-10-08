defmodule Wotex.Zigbee.ZCL.Configuration do
  @moduledoc """
  Explicit finite ZCL writes and reporting configuration with observed record outcomes.

  Constructors produce inert requests for revision 8 Write Attributes,
  Configure Reporting and Read Reporting Configuration. They never send,
  retry, bind, poll or change a device. A consumer authorizes the operation
  and puts the request payload in a `Wotex.Zigbee.DataRequest`.

  `observe/5` checks the AF request, current route custody and the received
  source, endpoints, cluster, direction, manufacturer and sequence. It retains
  the unchanged Event and original response bytes. Peer-reported success is
  separate from NCP admission, APS confirmation, authentication and physical
  effect. A successful Default Response does not establish record success.

  Matching does not establish that the request was dispatched. The consumer
  retains actual send/admission/APS observations and owns a finite correlation
  window with distinct AF transactions and ZCL sequences. Reusing context can
  match an old response; this pure module allocates no tokens or deadlines.

  Each request has at most 32 distinct records and 128 wire bytes. Writes use
  `Wotex.Zigbee.ZCL.Value`'s scalar/short-string profile. Reporting intervals
  are explicit seconds; cluster constraints and power policy remain consumer
  owned. Binding and commissioning are separate operations.
  """

  alias Wotex.Zigbee.{DataRequest, Error, Event, Routes}
  alias Wotex.Zigbee.ZCL.Configuration.{Codec, Request}

  @event_fields Map.keys(%Event{kind: nil, subsystem: nil, id: nil, payload: nil})

  @type response :: %{
          optional(:original_command) => byte(),
          optional(:status) => :success | {:error, byte()},
          command:
            :write_response | :configure_response | :read_reporting_response | :default_response,
          direction: Wotex.Zigbee.ZCL.direction(),
          manufacturer: non_neg_integer() | nil,
          sequence: byte(),
          aggregate: :all_success | :errors | :records | :default,
          records: [map()],
          raw: binary()
        }
  @type observation :: %{
          outcome: :reported_success | :partial | :unconfirmed,
          records: [map()],
          issues: [atom()],
          response: response(),
          event: Event.t(),
          correlation_id: binary()
        }

  @doc """
  Builds an inert ordinary Write Attributes request from distinct IDs.

  Each record has `id`, `type` and `value`, with optional numeric `full_range`
  policy (default false). Unknown fields/types, duplicate IDs, unsupported
  values and oversized frames fail. No undivided or no-response fallback occurs.
  """
  @spec write_attributes([map()], byte(), Wotex.Zigbee.ZCL.direction(), non_neg_integer() | nil) ::
          {:ok, Request.t()} | {:error, Error.t()}
  def write_attributes(records, sequence, direction, manufacturer \\ nil),
    do: build(:write_attributes, records, sequence, direction, manufacturer)

  @doc """
  Builds an explicit send/receive reporting configuration request.

  A `:send` record has `id`, `report_direction`, `type`, `min_interval_s` and
  `max_interval_s`, plus integer `change` for analog types only. A `:receive`
  record has `id`, `report_direction` and `timeout_s`. Intervals are uint16
  seconds; a nonzero maximum cannot be less than the minimum. Maximum
  `0xFFFF` disables reports. Minimum `0xFFFF` with maximum zero requests
  defaults. Both special modes require analog change zero. Other maximum-zero
  records retain change-based reporting. Signed changes retain their bytes;
  the revision specifies that the receiver ignores their sign.
  Minimum zero imposes no lower limit; receive timeout zero disables that
  reporting timeout. The record direction is separate from the ZCL header
  direction. Binding destinations and cluster-specific limits are consumer owned.
  """
  @spec configure_reporting(
          [map()],
          byte(),
          Wotex.Zigbee.ZCL.direction(),
          non_neg_integer() | nil
        ) ::
          {:ok, Request.t()} | {:error, Error.t()}
  def configure_reporting(records, sequence, direction, manufacturer \\ nil),
    do: build(:configure_reporting, records, sequence, direction, manufacturer)

  @doc "Builds a finite read of distinct `{report_direction, id}` reporting records."
  @spec read_reporting([map()], byte(), Wotex.Zigbee.ZCL.direction(), non_neg_integer() | nil) ::
          {:ok, Request.t()} | {:error, Error.t()}
  def read_reporting(records, sequence, direction, manufacturer \\ nil),
    do: build(:read_reporting, records, sequence, direction, manufacturer)

  @doc "Revalidates complete request fields, canonical records and wire bytes after copying."
  @spec valid_request?(term()) :: boolean()
  def valid_request?(%Request{} = request) do
    fields = [:command, :sequence, :direction, :manufacturer, :records, :payload]

    if map_size(request) == 7 and Enum.all?(fields, &Map.has_key?(request, &1)) do
      case build(
             request.command,
             request.records,
             request.sequence,
             request.direction,
             request.manufacturer
           ) do
        {:ok, canonical} -> canonical == request
        _ -> false
      end
    else
      false
    end
  end

  def valid_request?(_), do: false

  @doc """
  Decodes bounded write, configure, read-configuration or Default Response bytes.

  Aggregate success and failure-only records remain distinct. Record order and
  duplicates stay visible. Read-configuration failures have no configuration;
  standard non-value change remains null. An unsupported configuration type
  retains the entire remaining opaque tail without guessing later boundaries.
  This decoder supplies no source or request correlation by itself.
  """
  @spec decode_response(binary(), pos_integer()) :: {:ok, response()} | {:error, Error.t()}
  def decode_response(bytes, max_records \\ 32), do: Codec.decode(bytes, max_records)

  @doc """
  Correlates one source Event and reports inert outcomes in original request order.

  Only an exact current-custody source and inverse ZCL header can match. A
  well-formed failure-only response implies success for omitted request keys
  only if all response keys are expected and distinct. Anomalies preserve raw
  records and leave those omissions unconfirmed. Missing read-configuration
  records, duplicates and unsupported configuration stay unconfirmed. Default
  Responses retain command status and leave every record unconfirmed.
  """
  @spec observe(Request.t(), DataRequest.t(), Routes.t(), Event.t(), integer()) ::
          {:ok, observation()} | {:error, Error.t()}
  def observe(request, af_request, routes, %Event{} = event, now) do
    with true <-
           valid_request?(request) and DataRequest.valid?(af_request) and complete_event?(event),
         true <- request.payload == af_request.data,
         {:ok, source} <- Routes.resolve(routes, event, now),
         true <- source_matches?(source.entry, af_request, event),
         {:ok, response} <- decode_response(event.payload),
         true <- header_matches?(request, response) do
      {records, issues} = outcomes(request, response)
      outcome = outcome(records, issues)

      {:ok,
       %{
         outcome: outcome,
         records: records,
         issues: issues,
         response: response,
         event: event,
         correlation_id: af_request.correlation_id
       }}
    else
      false -> failure(:invalid_value)
      error -> error
    end
  end

  def observe(_, _, _, _, _), do: failure(:invalid_value)

  defp build(command, records, sequence, direction, manufacturer) do
    with {:ok, payload, canonical} <-
           Codec.encode(command, records, sequence, direction, manufacturer) do
      {:ok,
       %Request{
         command: command,
         records: canonical,
         sequence: sequence,
         direction: direction,
         manufacturer: manufacturer,
         payload: payload
       }}
    end
  end

  defp source_matches?(entry, request, event),
    do:
      event.kind == :af_incoming and event.subsystem == 4 and event.id == 0x81 and
        entry.peer_ieee == request.peer_ieee and
        event.source_address == request.route_address and
        event.source_endpoint == request.destination_endpoint and
        event.endpoint == request.source_endpoint and event.cluster == request.cluster

  defp complete_event?(event),
    do:
      map_size(event) == length(@event_fields) and
        Enum.all?(@event_fields, &Map.has_key?(event, &1))

  defp header_matches?(request, response) do
    expected = %{
      write_attributes: :write_response,
      configure_reporting: :configure_response,
      read_reporting: :read_reporting_response
    }

    wire_id = %{write_attributes: 2, configure_reporting: 6, read_reporting: 8}

    command_matches =
      response.command == expected[request.command] or
        (response.command == :default_response and
           response.original_command == wire_id[request.command])

    command_matches and response.sequence == request.sequence and
      response.manufacturer == request.manufacturer and
      response.direction != request.direction
  end

  defp outcomes(request, %{aggregate: :default}) do
    records = Enum.map(request.records, &row(&1, :unconfirmed, :default_response))
    {records, [:default_response]}
  end

  defp outcomes(request, response) do
    expected = Enum.map(request.records, &key(request.command, &1))
    actual = Enum.map(response.records, &key(request.command, &1))

    issues =
      []
      |> issue(length(actual) != length(Enum.uniq(actual)), :duplicate_record)
      |> issue(Enum.any?(actual, &(&1 not in expected)), :unexpected_record)

    rows = Enum.map(request.records, &record_outcome(request.command, &1, response, issues == []))

    issues =
      issues
      |> issue(Enum.any?(rows, &(&1.basis == :missing)), :missing_record)
      |> issue(Enum.any?(rows, &(&1.basis == :unsupported)), :unsupported_type)

    {rows, Enum.reverse(issues)}
  end

  defp record_outcome(command, record, response, clean) do
    matches = Enum.filter(response.records, &(key(command, &1) == key(command, record)))

    case {matches, response.aggregate, clean} do
      {[], :all_success, _} -> row(record, :success, :aggregate)
      {[], :errors, true} -> row(record, :success, :omitted_failure)
      {[], :errors, false} -> row(record, :unconfirmed, :ambiguous)
      {[], _, _} -> row(record, :unconfirmed, :missing)
      {[match], _, _} -> matched_row(record, match)
      {_, _, _} -> row(record, :unconfirmed, :ambiguous)
    end
  end

  defp matched_row(record, %{configuration: {:unsupported, _, _}} = match),
    do: row(record, :unconfirmed, :unsupported) |> Map.put(:configuration, match.configuration)

  defp matched_row(record, match),
    do:
      row(record, match.status, :record) |> Map.put(:configuration, Map.get(match, :configuration))

  defp row(record, status, basis), do: %{request: record, status: status, basis: basis}
  defp key(:write_attributes, record), do: record.id
  defp key(_, record), do: {record.report_direction, record.id}

  defp outcome(records, []) do
    if Enum.all?(records, &(&1.status == :success)), do: :reported_success, else: :partial
  end

  defp outcome(records, _) do
    if Enum.all?(records, &(&1.status == :unconfirmed)), do: :unconfirmed, else: :partial
  end

  defp issue(issues, true, issue), do: [issue | issues]
  defp issue(issues, false, _), do: issues
  defp failure(kind), do: {:error, %Error{kind: kind, operation: :zcl_configuration}}
end
