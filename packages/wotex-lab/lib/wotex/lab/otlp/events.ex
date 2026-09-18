defmodule Wotex.Lab.Otlp.Events do
  @moduledoc """
  Projects closing Lab telemetry spans into closed OTLP span and log records.

  Only `[:wotex, :lab, component, operation, :stop]` and `:exception` events
  with a catalogued component, operation and integer native `duration` are
  accepted. Each becomes one internal span named `component.operation` whose
  end is the observation time and whose start subtracts the duration. Span
  attributes are drawn only from closed vocabularies: `wotex.lab.component`,
  `wotex.lab.operation`, `wotex.lab.outcome_class` through
  `Wotex.Lab.Metrics.Catalogue.outcome_class/1`, `wotex.lab.profile` and, for
  an exception, `wotex.lab.kind`. The status is OK only for the `ok` outcome
  class. An exception additionally yields one ERROR log record with the fixed
  body `wotex.lab span exception` and event name `wotex.lab.span.exception`.

  Thing references, scenario identifiers, attempt numbers and every other
  metadata value are dropped, so payloads, identifiers and exception reasons
  cannot reach an exporter. Each span carries caller-supplied random trace and
  span identifiers; Lab spans are not linked to a parent or propagated trace.
  """

  alias Wotex.Lab.Metrics.Catalogue
  alias Wotex.Lab.Otlp.Encoder
  alias Wotex.Lab.Telemetry

  @components Telemetry.components()
  @operations Telemetry.operations()

  @typedoc "Observation time and identifiers supplied by the exporter."
  @type context :: %{
          end_ns: non_neg_integer(),
          trace_id: <<_::128>>,
          span_id: <<_::64>>
        }

  @doc "The telemetry events the projection accepts."
  @spec events() :: [[atom()]]
  def events do
    for component <- @components, operation <- @operations, kind <- [:stop, :exception] do
      [:wotex, :lab, component, operation, kind]
    end
  end

  @doc "Projects one closing event into a span and, for an exception, a log record."
  @spec project([atom()], map(), map(), context()) ::
          {:ok, Encoder.span(), Encoder.log() | nil} | :ignore
  def project(
        [:wotex, :lab, component, operation, kind] = event,
        %{duration: duration},
        metadata,
        %{end_ns: end_ns, trace_id: <<_::128>> = trace_id, span_id: <<_::64>> = span_id}
      )
      when component in @components and operation in @operations and
             kind in [:stop, :exception] and is_integer(duration) and duration >= 0 and
             is_map(metadata) and is_integer(end_ns) and end_ns >= 0 do
    outcome =
      if kind == :exception,
        do: :exception,
        else: Catalogue.dimension_value(:outcome_class, event, metadata, %{})

    base = [
      {"wotex.lab.component", Atom.to_string(component)},
      {"wotex.lab.operation", Atom.to_string(operation)},
      {"wotex.lab.outcome_class", Atom.to_string(outcome)},
      {"wotex.lab.profile",
       Atom.to_string(Catalogue.dimension_value(:profile, event, metadata, %{}))}
    ]

    kind_attributes =
      if kind == :exception,
        do: [
          {"wotex.lab.kind", Atom.to_string(Catalogue.dimension_value(:kind, event, metadata, %{}))}
        ],
        else: []

    attributes = base ++ kind_attributes

    span = %{
      trace_id: trace_id,
      span_id: span_id,
      name: "#{component}.#{operation}",
      start_ns: max(end_ns - System.convert_time_unit(duration, :native, :nanosecond), 0),
      end_ns: end_ns,
      attributes: attributes,
      status: if(outcome == :ok, do: :ok, else: :error)
    }

    {:ok, span, log(kind, end_ns, attributes)}
  end

  def project(_, _, _, _), do: :ignore

  defp log(:stop, _, _), do: nil

  defp log(:exception, time_ns, attributes) do
    %{
      time_ns: time_ns,
      observed_ns: time_ns,
      severity: :error,
      body: "wotex.lab span exception",
      event_name: "wotex.lab.span.exception",
      attributes: attributes
    }
  end
end
