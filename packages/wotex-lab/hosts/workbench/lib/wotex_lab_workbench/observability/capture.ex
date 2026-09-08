defmodule WotexLabWorkbench.Observability.Capture do
  @moduledoc """
  Public PromEx exposition paired with the host adapter's matching receipt.

  Text alone has no collector reset identity or loss counters. The receipt
  binds those fields and capture clocks to the SHA-256 of the actual body.
  A racing scrape with different contents or collector restart is refused,
  not joined to unrelated metadata. Only one bounded attempt is made. No
  private PromEx/Peep function, state or table is accessed.
  """

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{Exposition, Snapshot}
  alias WotexLabWorkbench.Observability.Store

  @promex WotexLabWorkbench.Observability.PromEx

  @doc "Captures this explicitly started host collector without self-HTTP."
  @spec sample() :: {:ok, Snapshot.t()} | {:error, Error.t()}
  def sample do
    with {:ok, store} <- store(),
         text when is_binary(text) <- PromEx.get_metrics(@promex),
         {:ok, receipt} <- Store.receipt(store, text),
         {:ok, parsed} <- Exposition.parse(text) do
      receipt
      |> Map.merge(%{source: :exposition, series: parsed.series})
      |> Snapshot.new()
    else
      {:error, _error} = error -> error
      _unavailable -> unavailable()
    end
  catch
    :exit, _reason -> unavailable()
  end

  defp store do
    @promex
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {_id, pid, :worker, [Store]} when is_pid(pid) -> {:ok, pid}
      _child -> nil
    end)
    |> case do
      nil -> unavailable()
      found -> found
    end
  end

  defp unavailable,
    do: {:error, Error.new(:collector_unavailable, :metrics, "collector unavailable")}
end
