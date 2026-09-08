defmodule WotexLabWorkbench.Observability.PromEx do
  @moduledoc """
  Explicit PromEx reference for the Workbench Lab instance.

  Only the reviewed catalogue plugin is activated. There is no Grafana agent,
  dashboard upload, self-HTTP listener or runtime dependency download. Raw
  BEAM/Phoenix/LiveView introspection is not enabled by this custom-metric
  cohort; its separate host-wide admission remains required before activation.
  """

  use PromEx, otp_app: :wotex_lab_workbench

  alias WotexLabWorkbench.Observability.Plugin

  @impl PromEx
  def plugins, do: [Plugin]

  @impl PromEx
  def init_opts do
    PromEx.Config.build(
      grafana: :disabled,
      grafana_agent: :disabled,
      metrics_server: :disabled,
      drop_metrics_groups: [:prom_ex_manual_metrics]
    )
  end
end
