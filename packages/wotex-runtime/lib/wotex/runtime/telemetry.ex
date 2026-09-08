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
  | `[:wotex, :runtime, :request, :exception]` | `duration` | request identity, `kind`, `code` |
  | `[:wotex, :runtime, :port, :exception]` | `system_time` | request identity, port `callback`, `kind`, `code` |
  | `[:wotex, :runtime, :subscription, :open]` | `system_time` | subscription identity |
  | `[:wotex, :runtime, :subscription, :close]` | `system_time` | subscription identity, normalized `outcome`, optional `code` |
  | `[:wotex, :runtime, :subscription, :deliver]` | `system_time` | subscription identity, `outcome` |
  | `[:wotex, :runtime, :subscription, :drop]` | `system_time`, `queue_length` | subscription identity |
  | `[:wotex, :runtime, :subscription, :status]` | `system_time` | subscription identity, `status` |

  Raw raised reasons and stacktraces are deliberately omitted because consumer
  ports may embed credentials or protocol payloads in those terms.
  """

  @doc false
  @spec span([atom()], map(), (-> {term(), map()})) :: term()
  def span(event, metadata, fun) when is_list(event) and is_map(metadata) do
    started_at = System.monotonic_time()
    execute(event ++ [:start], metadata)

    try do
      {result, stop_metadata} = fun.()

      execute(
        event ++ [:stop],
        %{duration: System.monotonic_time() - started_at},
        stop_metadata
      )

      result
    catch
      kind, reason ->
        execute(
          event ++ [:exception],
          %{duration: System.monotonic_time() - started_at},
          Map.merge(metadata, %{kind: kind, code: :request_exception})
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
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
