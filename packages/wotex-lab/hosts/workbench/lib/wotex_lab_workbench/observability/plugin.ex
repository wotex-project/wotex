defmodule WotexLabWorkbench.Observability.Plugin do
  @moduledoc "Custom PromEx plugin generated exclusively from the Lab metric catalogue."

  @behaviour PromEx.Plugin

  alias PromEx.MetricTypes.Event
  alias WotexLabWorkbench.Observability.Definitions

  @impl PromEx.Plugin
  def event_metrics(_opts) do
    # The explicit host storage adapter consumes catalogue buckets directly;
    # no runtime-generated Peep bucket modules are required.
    %Event{group_name: :wotex_lab_catalogue_event_metrics, metrics: Definitions.metrics()}
  end

  @impl PromEx.Plugin
  def polling_metrics(_opts), do: []

  @impl PromEx.Plugin
  def manual_metrics(_opts), do: []
end
