defmodule Wotex.Runtime.Telemetry do
  @moduledoc """
  Telemetry events emitted by the runtime.

  Events carry only non-secret identity: operation, affordance type and name,
  request id, profile id, and subscription id. Credential material, transport
  payloads, and external error terms are never included. Attaching handlers is
  the consumer's decision; the runtime starts no process for this.

  | Event | Measurements | Metadata |
  | --- | --- | --- |
  | `[:wotex, :runtime, :request, :start]` | `system_time` | request identity |
  | `[:wotex, :runtime, :request, :stop]` | `duration` | request identity, `result` (`:ok` or `:error`), `code` |
  | `[:wotex, :runtime, :request, :exception]` | `duration` | request identity, `kind`, `reason`, `stacktrace` |
  | `[:wotex, :runtime, :port, :exception]` | `system_time` | port `callback`, `kind`, `reason`, `stacktrace` |
  | `[:wotex, :runtime, :subscription, :open]` | `system_time` | subscription identity |
  | `[:wotex, :runtime, :subscription, :close]` | `system_time` | subscription identity, `reason` |
  | `[:wotex, :runtime, :subscription, :deliver]` | `system_time` | subscription identity, `outcome` |
  | `[:wotex, :runtime, :subscription, :drop]` | `system_time`, `queue_length` | subscription identity |
  | `[:wotex, :runtime, :subscription, :status]` | `system_time` | subscription identity, `status` |

  Port exception metadata contains the raised reason so a consumer handler can
  log an adapter defect; that reason never enters a public error value.
  """

  @doc false
  @spec span([atom()], map(), (-> {term(), map()})) :: term()
  def span(event, metadata, fun) when is_list(event) and is_map(metadata) do
    :telemetry.span([:wotex, :runtime | event], metadata, fun)
  end

  @doc false
  @spec execute([atom()], map(), map()) :: :ok
  def execute(event, measurements \\ %{}, metadata) when is_list(event) do
    :telemetry.execute(
      [:wotex, :runtime | event],
      Map.put_new(measurements, :system_time, System.system_time()),
      metadata
    )
  end
end
