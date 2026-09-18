defmodule WotexLabWorkbench.Observability.Plugin do
  @moduledoc """
  Supplies the Workbench's catalogue-defined event metrics to PromEx.

  Event definitions come from `WotexLabWorkbench.Observability.Definitions` as
  one named group. Polling and manual metric lists are empty, so this plugin
  requests no periodic host inspection. The explicitly configured reference
  host owns PromEx activation and storage; loading this module neither attaches
  a collector nor opens an exporter.
  """

  @behaviour PromEx.Plugin

  alias PromEx.MetricTypes.Event
  alias WotexLabWorkbench.Observability.Definitions

  @impl PromEx.Plugin
  def event_metrics(_) do
    # The explicit host storage adapter consumes catalogue buckets directly;
    # no runtime-generated Peep bucket modules are required.
    %Event{group_name: :wotex_lab_catalogue_event_metrics, metrics: Definitions.metrics()}
  end

  @impl PromEx.Plugin
  def polling_metrics(_), do: []

  @impl PromEx.Plugin
  def manual_metrics(_), do: []
end
