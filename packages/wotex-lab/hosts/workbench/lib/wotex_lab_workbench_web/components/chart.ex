defmodule WotexLabWorkbenchWeb.Components.Chart do
  @moduledoc "A bounded chart with server-rendered SVG and a visible data-table alternative."

  use Phoenix.Component

  alias WotexLabWorkbench.Chart
  alias WotexLabWorkbench.Preview

  attr :id, :string, required: true
  attr :chart, :any, required: true

  @doc "Renders admitted chart geometry and the same points as an accessible table."
  @spec chart(map()) :: Phoenix.LiveView.Rendered.t()
  def chart(%{chart: %Chart{} = chart} = assigns) do
    rows =
      chart.series
      |> Stream.flat_map(fn series ->
        Stream.map(series.points, fn {x, y} -> %{series: series.name, x: x, y: y} end)
      end)
      |> Enum.take(100)

    assigns =
      assigns
      |> assign(:geometry, Chart.geometry(chart))
      |> assign(:rows, rows)
      |> assign(:total, Enum.sum(Enum.map(chart.series, &length(&1.points))))
      |> assign(:spec, Jason.encode!(chart.spec))

    ~H"""
    <figure id={@id} class="wl-chart" phx-hook="WotexChart" data-spec={@spec}>
      <figcaption id={"#{@id}-caption"}>{@chart.title}</figcaption>
      <p id={"#{@id}-description"}>
        {@chart.mark} chart. Horizontal axis: {@chart.x.title}; vertical axis: {@chart.y.title}.
        Missing values are gaps. The table below previews at most 100 points.
      </p>
      <div
        id={"#{@id}-enhanced"}
        class="wl-chart-enhanced"
        phx-update="ignore"
        aria-hidden="true"
        hidden
      />
      <button type="button" data-chart-reset hidden>Reset chart zoom</button>
      <svg
        class="wl-chart-svg"
        viewBox={"0 0 #{@geometry.width} #{@geometry.height}"}
        role="img"
        aria-labelledby={"#{@id}-caption"}
        aria-describedby={"#{@id}-description"}
      >
        <title>{@chart.title}</title>
        <desc>{@chart.x.title} against {@chart.y.title}; missing values break the series.</desc>
        <rect
          class="wl-chart-plot"
          x={@geometry.plot.x}
          y={@geometry.plot.y}
          width={@geometry.plot.width}
          height={@geometry.plot.height}
        />
        <g :for={tick <- @geometry.x_ticks} class="wl-chart-axis">
          <line
            x1={tick.px}
            x2={tick.px}
            y1={@geometry.plot.y}
            y2={@geometry.plot.y + @geometry.plot.height}
          />
          <text x={tick.px} y={@geometry.height - 28} text-anchor="middle">
            {Preview.format(tick.value)}
          </text>
        </g>
        <g :for={tick <- @geometry.y_ticks} class="wl-chart-axis">
          <line
            x1={@geometry.plot.x}
            x2={@geometry.plot.x + @geometry.plot.width}
            y1={tick.px}
            y2={tick.px}
          />
          <text x={@geometry.plot.x - 8} y={tick.px} text-anchor="end" dominant-baseline="middle">
            {Preview.format(tick.value)}
          </text>
        </g>
        <text
          class="wl-chart-axis-title"
          x={@geometry.width / 2}
          y={@geometry.height - 6}
          text-anchor="middle"
        >
          {@chart.x.title}
        </text>
        <text
          class="wl-chart-axis-title"
          transform={"translate(14 #{@geometry.height / 2}) rotate(-90)"}
          text-anchor="middle"
        >
          {@chart.y.title}
        </text>
        <g
          :for={{series, index} <- Enum.with_index(@geometry.series)}
          class={"wl-chart-series wl-series-#{rem(index, 8)}"}
        >
          <%= case @chart.mark do %>
            <% "line" -> %>
              <polyline :for={points <- series.segments} points={points} />
            <% "point" -> %>
              <circle :for={point <- series.points} cx={point.x} cy={point.y} r="3" />
            <% "area" -> %>
              <polygon :for={points <- series.areas} points={points} />
          <% end %>
        </g>
      </svg>
      <ul class="wl-chart-legend" aria-label="Series legend">
        <li :for={{series, index} <- Enum.with_index(@geometry.series)} class={"wl-series-#{index}"}>
          <span aria-hidden="true" class="wl-chart-swatch" />{series.name}: {series.gaps} missing
        </li>
      </ul>
      <details class="wl-chart-table">
        <summary>Data table alternative ({length(@rows)} of {@total} points)</summary>
        <p :if={@total > length(@rows)}>Preview truncated; the chart retains the admitted points.</p>
        <div class="wl-table-wrap">
          <table>
            <caption>{@chart.title} data</caption>
            <thead>
              <tr>
                <th scope="col">Series</th><th scope="col">{@chart.x.title}</th><th scope="col">
                  {@chart.y.title}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @rows}>
                <td>{row.series}</td><td>{row.x}</td><td>
                  {if is_nil(row.y), do: "missing", else: row.y}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </details>
    </figure>
    """
  end
end
