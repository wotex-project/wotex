defmodule WotexLabWorkbenchWeb.Components.RunResult do
  @moduledoc "Compact outcome, charts and contextual controls for an already completed Run."

  use WotexLabWorkbenchWeb, :html

  alias Wotex.Lab.Evidence.Record
  alias WotexLabWorkbench.{Run, RunPresentation}
  alias WotexLabWorkbenchWeb.Components.StatusBadge

  attr(:run, :any, required: true)
  attr(:charts, :list, required: true)
  attr(:chart_links, :list, required: true)
  attr(:analysed, :boolean, default: false)

  @doc "Renders the outcome first; opening a contextual view executes no operation."
  @spec run_result(map()) :: Phoenix.LiveView.Rendered.t()
  def run_result(assigns) do
    charts =
      assigns.charts
      |> Enum.with_index()
      |> Enum.filter(fn {chart, _} -> Enum.any?(chart.series, &(length(&1.points) > 1)) end)

    assigns = assign(assigns, result: RunPresentation.result(assigns.run), result_charts: charts)

    ~H"""
    <div id="wl-run-result" class="wl-run-result wl-stack">
      <div class="wl-run-state">
        <.status_badge status={Run.state_text(@run)} kind={StatusBadge.kind_for(@run.status)} />
        <span class="wl-muted">{@run.duration_ms} ms</span>
      </div>
      <section :if={is_nil(@run.error)} aria-label={@result.label} class="wl-run-outcome">
        <p class="wl-muted">{@result.label}</p>
        <div class="wl-run-value"><strong>{@result.value}</strong><span>{@result.unit}</span></div>
        <p>{@result.note}</p>
      </section>
      <.error_state
        :if={@run.error}
        title="Run failed"
        code={@run.error.code}
        message={@run.error.message}
      />
      <dl :if={@result.facts != [] && is_nil(@run.error)} class="wl-run-facts">
        <div :for={{label, value} <- @result.facts}>
          <dt>{label}</dt><dd>{value || "—"}</dd>
        </div>
      </dl>
      <div :if={@run.status == :awaiting_approval} class="wl-actions">
        <.link patch={RunPresentation.path(@run, :review)} class="wl-button wl-button-primary">Review Action</.link>
        <button
          type="button"
          class="wl-button wl-button-secondary"
          phx-click="cancel"
          phx-value-id={@run.id}
        >Cancel run</button>
      </div>
      <div :if={@result_charts != []} class="wl-run-charts">
        <p :if={@analysed} class="wl-muted">Filtered analysis</p>
        <%= for {{chart, index}, position} <- Enum.with_index(@result_charts) do %>
          <.chart
            :if={position == 0}
            id={"run-chart-#{index}"}
            chart={RunPresentation.display_chart(@run, chart)}
            permalink={Enum.at(@chart_links, index)}
            compact
          />
          <details :if={position > 0} class="wl-disclosure">
            <summary>
              {if @run.experiment == "window_anomaly", do: "Window chart", else: chart.title}
            </summary>
            <.chart
              id={"run-chart-#{index}"}
              chart={RunPresentation.display_chart(@run, chart)}
              permalink={Enum.at(@chart_links, index)}
              compact
            />
          </details>
        <% end %>
      </div>
      <nav class="wl-run-tools" aria-label="Run tools">
        <.link :if={@run.tensor} patch={RunPresentation.path(@run, :data)}>Data</.link>
        <.link :if={@run.timeseries != []} patch={RunPresentation.path(@run, :analysis)}>Analysis</.link>
        <.link patch={RunPresentation.path(@run, :details)}>Run details</.link>
        <.link patch={"/evidence?" <> URI.encode_query(%{"run" => @run.id})}>Sources</.link>
        <.link patch={RunPresentation.path(@run, :ask)}>Ask</.link>
        <a href={RunPresentation.report_path(@run)} download>Export report</a>
      </nav>
    </div>
    """
  end

  attr(:run, :any, required: true)

  @doc "Shows exact recorded inputs and provenance without selecting another Run."
  @spec run_sources(map()) :: Phoenix.LiveView.Rendered.t()
  def run_sources(assigns) do
    assigns = assign(assigns, :record, assigns.run.record && Record.to_map(assigns.run.record))

    ~H"""
    <section id="wl-run-sources" aria-label="Run sources" class="wl-stack">
      <dl class="wl-meta-list">
        <dt>Run</dt><dd>{@run.id}</dd>
        <dt>State</dt><dd>{Run.state_text(@run)}</dd>
        <dt>Record digest</dt><dd><code>{@run.record_digest || "Unavailable"}</code></dd>
        <dt>Backend</dt><dd>{@run.backend}</dd>
        <dt>Source mode</dt><dd>{@run.source_mode}</dd>
      </dl>
      <section :if={@run.record} aria-label="Recorded inputs" class="wl-stack">
        <h3>Inputs</h3>
        <ul class="wl-source-inputs">
          <li :for={input <- @run.record.inputs}><code>{input}</code></li>
        </ul>
      </section>
      <details :if={@record} class="wl-disclosure">
        <summary>Full record</summary>
        <pre><code>{Jason.encode!(@record, pretty: true)}</code></pre>
      </details>
      <div class="wl-actions">
        <.link patch={RunPresentation.path(@run, :details)} class="wl-button wl-button-secondary">Run details</.link>
        <a href={RunPresentation.report_path(@run)} download class="wl-button wl-button-secondary">Export report</a>
      </div>
    </section>
    """
  end
end
