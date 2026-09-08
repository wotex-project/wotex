defmodule WotexLabWorkbenchWeb.Components.Chart do
  @moduledoc "A bounded chart with server-rendered SVG and a visible data-table alternative."

  use Phoenix.Component

  alias WotexLabWorkbench.Chart

  attr :id, :string, required: true
  attr :chart, :any, required: true

  @doc "Renders admitted chart geometry and the same points as an accessible table."
  @spec chart(map()) :: Phoenix.LiveView.Rendered.t()
  def chart(%{chart: %Chart{} = chart} = assigns) do
    rows =
      for series <- chart.series, {x, y} <- series.points do
        %{series: series.name, x: x, y: y}
      end

    assigns =
      assigns
      |> assign(:geometry, Chart.geometry(chart))
      |> assign(:rows, rows)
      |> assign(:spec, Jason.encode!(chart.spec))

    ~H"""
    <figure id={@id} class="wl-chart" phx-hook="WotexChart" data-spec={@spec}>
      <figcaption id={"#{@id}-caption"}>{@chart.title}</figcaption>
      <svg
        class="wl-chart-svg"
        viewBox={"0 0 #{@geometry.width} #{@geometry.height}"}
        role="img"
        aria-labelledby={"#{@id}-caption"}
      >
        <rect
          class="wl-chart-plot"
          x={@geometry.plot.x}
          y={@geometry.plot.y}
          width={@geometry.plot.width}
          height={@geometry.plot.height}
        />
        <g
          :for={{series, index} <- Enum.with_index(@geometry.series)}
          class={"wl-chart-series wl-series-#{rem(index, 8)}"}
        >
          <polyline :for={points <- series.segments} points={points} />
        </g>
      </svg>
      <details class="wl-chart-table">
        <summary>Data table alternative ({length(@rows)} points)</summary>
        <div class="wl-table-wrap">
          <table>
            <caption>{@chart.title} data</caption>
            <thead>
              <tr>
                <th scope="col">Series</th><th scope="col">x</th><th scope="col">y</th>
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
