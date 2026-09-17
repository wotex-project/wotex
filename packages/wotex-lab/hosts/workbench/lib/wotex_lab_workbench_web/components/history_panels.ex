defmodule WotexLabWorkbenchWeb.Components.HistoryPanels do
  @moduledoc """
  Renders the explicit history query form and the supplied saved-panel results.

  Submitting `load_history` requests one closed range for the saved or
  previewed arrangement. The LiveView queries the session room through
  `WotexLabWorkbench.HistoryPanels`; rendering performs no query. Each panel
  states its aggregation, status, freshness, shown and total label sets,
  history markers and query digests. Charts keep missing steps as gaps, and a
  panel without captured series says so instead of drawing zero.
  """

  use Phoenix.Component

  import WotexLabWorkbenchWeb.Components.Chart
  import WotexLabWorkbenchWeb.Components.EmptyState
  import WotexLabWorkbenchWeb.Components.Field
  import WotexLabWorkbenchWeb.Components.MetricPanel

  alias WotexLabWorkbench.HistoryPanels

  attr :history, :any, required: true
  attr :range, :string, required: true

  @doc "Renders the history form and any supplied panel results."
  @spec history_panels(map()) :: Phoenix.LiveView.Rendered.t()
  def history_panels(assigns) do
    assigns = assign(assigns, :ranges, Enum.map(HistoryPanels.ranges(), &{&1, &1}))

    ~H"""
    <section id="history-panels" class="wl-panel" aria-labelledby="history-heading">
      <header class="wl-panel-header">
        <h2 id="history-heading">Session history panels</h2>
      </header>
      <p>
        The saved panels query this room's own bounded history. It holds catalogue events from
        the room, the processes it started and the tasks it awaits. Things' server processes,
        shared host processes and other sessions are not included. Missing steps are gaps, not zeros.
      </p>
      <form id="history-query" phx-submit="load_history" class="wl-filter-bar">
        <.field
          id="history-range"
          name="range"
          label="Range"
          type="select"
          value={@range}
          options={@ranges}
        /><button
          class="wl-button wl-button-secondary"
          type="submit"
          phx-disable-with="Querying…"
        >Load history</button>
      </form>
      <.empty_state
        :if={is_nil(@history)}
        title="History not loaded"
        description="Opening this page runs no query. Load history to query the saved panels."
      />
      <div :if={@history} id="history-results" class="wl-stack" aria-live="polite">
        <p class="wl-muted">
          Range {@history.range} ending {format_time(@history.end_ms)}, in {step_seconds(@history)}-second
          steps. Rates start at the first capture inside the range.
        </p>
        <.metric_panel
          :for={panel <- @history.panels}
          title={panel.title}
          status={status_text(panel)}
          note={note(panel)}
          value_visible={false}
        >
          <.chart :if={panel.chart} id={"history-chart-#{panel.id}"} chart={panel.chart} />
          <p :if={is_nil(panel.chart)}>{absence(panel)}</p>
          <details :if={panel.digests != []}>
            <summary>Query digests ({length(panel.digests)})</summary>
            <ul>
              <li :for={digest <- panel.digests}><code class="wl-query-code">{digest}</code></li>
            </ul>
          </details>
        </.metric_panel>
      </div>
    </section>
    """
  end

  defp status_text(%{status: :available}), do: "available"
  defp status_text(%{status: :unavailable}), do: "unavailable"
  defp status_text(%{status: :not_queried}), do: "not queried"
  defp status_text(%{status: :refused}), do: "refused"

  defp note(panel) do
    markers =
      panel.markers
      |> Enum.filter(fn {_, count} -> count > 0 end)
      |> Enum.sort()
      |> Enum.map_join(", ", fn {kind, count} -> "#{kind} #{count}" end)

    [
      "#{panel.aggregation} in #{panel.display_unit}",
      "#{panel.series_shown} of #{panel.series_total} label sets",
      freshness(panel.freshness_ms),
      if(markers == "", do: "no history markers", else: "markers: " <> markers)
    ]
    |> Enum.join("; ")
  end

  defp freshness(nil), do: "freshness unknown"
  defp freshness(age_ms), do: "latest capture #{age_ms} ms before load"

  defp absence(%{status: :unavailable}),
    do: "No captured series in this range; nothing is drawn as zero."

  defp absence(%{status: :not_queried}),
    do: "The history query budget was exhausted before this panel."

  defp absence(%{error: error}), do: "The history refused this query: #{error}."

  defp step_seconds(history), do: div(history.step_ms, 1_000)

  defp format_time(ms) do
    ms |> DateTime.from_unix!(:millisecond) |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
