defmodule WotexLabWorkbenchWeb.Components.Insights do
  @moduledoc "Keyboard-accessible analysis controls and missing-aware Explorer summaries."

  use Phoenix.Component

  import WotexLabWorkbenchWeb.Components.DataTable
  alias WotexLabWorkbench.{Insights, Preview}

  attr :run, :any, required: true
  attr :insights, :any, required: true

  @doc "Renders explicit analysis controls; no native work is performed during rendering."
  @spec insights(map()) :: Phoenix.LiveView.Rendered.t()
  def insights(assigns) do
    query =
      if assigns.insights, do: assigns.insights.query, else: %{series: nil, from: nil, to: nil}

    assigns =
      assigns
      |> assign(:query, query)
      |> assign(:deep_link, if(assigns.insights, do: Insights.path(assigns.insights)))

    ~H"""
    <section class="wl-section" aria-labelledby="analysis-heading">
      <h2 id="analysis-heading">Explore this run</h2>
      <p>
        Filter and compare the bounded run preview with Explorer. This does not re-run the experiment,
        change its evidence, or create training data. Units stay separate; missing values never become zero.
      </p>
      <form id="run-analysis" phx-submit="inspect_run" class="wl-filter-bar">
        <div>
          <label for="analysis-series">Series</label>
          <select id="analysis-series" name="series">
            <option value="" selected={is_nil(@query.series)}>All series</option>
            <option
              :for={series <- @run.timeseries}
              value={series.name}
              selected={@query.series == series.name}
            >
              {series.name}
            </option>
          </select>
        </div>
        <div>
          <label for="analysis-from">Event time from</label>
          <input id="analysis-from" name="from" type="number" step="any" value={@query.from} />
        </div>
        <div>
          <label for="analysis-to">Event time to</label>
          <input id="analysis-to" name="to" type="number" step="any" value={@query.to} />
        </div>
        <div>
          <label for="analysis-mark">Chart mark</label>
          <select id="analysis-mark" name="mark">
            <option
              :for={mark <- ~w(line point area)}
              value={mark}
              selected={mark == if @insights, do: @insights.mark, else: "line"}
            >
              {mark}
            </option>
          </select>
        </div>
        <button type="submit" phx-disable-with="Inspecting…">Apply analysis</button>
      </form>
      <div :if={@insights} id="run-insights">
        <p role="status">
          {@insights.total_rows} matching points; {length(@insights.preview)} preview rows. {if @insights.truncated,
            do: "Preview truncated."}
        </p>
        <dl class="wl-provenance">
          <div>
            <dt>Source preview digest</dt><dd><code>{@insights.source_digest}</code></dd>
          </div>
          <div>
            <dt>Analysis query digest</dt><dd><code>{@insights.query_digest}</code></dd>
          </div>
          <div>
            <dt>Backend</dt><dd>{@insights.backend}</dd>
          </div>
        </dl>
        <a id="analysis-deep-link" class="wl-button wl-button-secondary" href={@deep_link}>
          Exact analysis link
        </a>
        <p :if={@insights.total_rows == 0}>No points match this range. This is not a measured zero.</p>
        <.data_table
          id="analysis-summary"
          caption="Explorer summary of matching preview points"
          rows={@insights.summary}
        >
          <:col :let={row} label="Series">{row["series"]}</:col>
          <:col :let={row} label="Unit">{row["unit"]}</:col>
          <:col :let={row} label="Observed">{row["observed"]}</:col>
          <:col :let={row} label="Missing">{row["missing"]}</:col>
          <:col :let={row} label="Nonfinite">{row["nonfinite"]}</:col>
          <:col :let={row} label="Mean">{Preview.format(row["mean"])}</:col>
          <:col :let={row} label="Minimum">{Preview.format(row["minimum"])}</:col>
          <:col :let={row} label="Maximum">{Preview.format(row["maximum"])}</:col>
        </.data_table>
        <.data_table id="analysis-preview" caption="Filtered data preview" rows={@insights.preview}>
          <:col :let={row} label="Series">{row["series"]}</:col>
          <:col :let={row} label="Event time">{Preview.format(row["x"])}</:col>
          <:col :let={row} label="Value">{Preview.format(row["value"])}</:col>
          <:col :let={row} label="Unit">{row["unit"]}</:col>
          <:col :let={row} label="State">{row["state"]}</:col>
        </.data_table>
        <p :for={series <- @insights.series}>
          {series.name}: {series.source}; {series.points} source points;
          downsampling {series.method}, interval {inspect(series.interval)}, {series.dropped} dropped.
        </p>
      </div>
    </section>
    """
  end
end
