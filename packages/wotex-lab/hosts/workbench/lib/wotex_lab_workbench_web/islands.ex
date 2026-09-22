defmodule WotexLabWorkbenchWeb.Islands do
  @moduledoc """
  Closed Workbench projections for the registered Wotex Lab islands.

  The functions in this module expose only bounded presentation data. The
  surrounding LiveView retains the session, room, run, query and command
  identities, while each island keeps its semantic HEEx fallback beside the
  ignored Svelte mount root.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS
  alias Wotex.Lab.Island.{Event, Snapshot}
  alias WotexLabWorkbench.Chart

  @type descriptor :: %{component: String.t(), id: String.t(), props: map()}

  attr(:id, :string, required: true)
  attr(:chart, :any, required: true)
  attr(:revision, :integer, required: true)
  slot(:fallback, required: true)

  @doc "Enhances one admitted chart while retaining its native SVG and table fallback."
  @spec chart_island(map()) :: Phoenix.LiveView.Rendered.t()
  def chart_island(%{chart: %Chart{}} = assigns) do
    assigns = assign(assigns, :props, chart_props(assigns.chart))

    ~H"""
    <.island_boundary
      id={@id}
      component="chart"
      props={@props}
      generation="0"
      revision={to_string(@revision)}
      capabilities={["inspect"]}
    >
      <:fallback>{render_slot(@fallback)}</:fallback>
    </.island_boundary>
    """
  end

  attr(:id, :string, required: true)
  attr(:label, :string, required: true)
  attr(:columns, :list, required: true)
  attr(:rows, :list, required: true)
  attr(:revision, :integer, required: true)
  slot(:fallback, required: true)

  @doc "Enhances one bounded table with the registered keyboard data grid."
  @spec data_grid_island(map()) :: Phoenix.LiveView.Rendered.t()
  def data_grid_island(assigns) do
    assigns = assign(assigns, :props, data_grid_props(assigns.label, assigns.columns, assigns.rows))

    ~H"""
    <.island_boundary
      id={@id}
      component="data-grid"
      props={@props}
      generation="0"
      revision={to_string(@revision)}
      capabilities={["select", "activate"]}
    >
      <:fallback>{render_slot(@fallback)}</:fallback>
    </.island_boundary>
    """
  end

  attr(:id, :string, required: true)
  attr(:label, :string, required: true)
  attr(:tabs, :list, required: true)
  attr(:selected, :string, required: true)
  attr(:revision, :integer, required: true)
  slot(:fallback, required: true)

  @doc "Enhances a small local information switcher with registered tabs."
  @spec tabs_island(map()) :: Phoenix.LiveView.Rendered.t()
  def tabs_island(assigns) do
    assigns = assign(assigns, :props, tabs_props(assigns.label, assigns.tabs, assigns.selected))

    ~H"""
    <.island_boundary
      id={@id}
      component="tabs"
      props={@props}
      generation="0"
      revision={to_string(@revision)}
      capabilities={["select"]}
    >
      <:fallback>{render_slot(@fallback)}</:fallback>
    </.island_boundary>
    """
  end

  attr(:id, :string, required: true)
  attr(:component, :string, required: true)
  attr(:props, :map, required: true)
  attr(:generation, :string, required: true)
  attr(:revision, :string, required: true)
  attr(:capabilities, :list, required: true)
  slot(:fallback, required: true)

  defp island_boundary(assigns) do
    {:ok, snapshot} =
      Snapshot.new(assigns.component, assigns.id, assigns.props,
        generation: assigns.generation,
        revision: assigns.revision,
        capabilities: assigns.capabilities
      )

    {:ok, encoded} = Snapshot.encode_inline(snapshot)

    assigns =
      assigns
      |> assign(:encoded, encoded)
      |> assign(:mount_id, assigns.id <> "--svelte")
      |> assign(:fallback_id, assigns.id <> "--fallback")
      |> assign(:ignore_readiness, JS.ignore_attributes(["data-wotex-island-state"]))

    ~H"""
    <section
      id={@id}
      data-wotex-island={@component}
      data-wotex-island-state="loading"
      data-wotex-design-system
      phx-mounted={@ignore_readiness}
    >
      <div id={@fallback_id} data-wotex-island-fallback>
        {render_slot(@fallback)}
      </div>
      <div
        id={@mount_id}
        data-wotex-island-mount
        data-wotex-island-instance={@id}
        data-wotex-island-component={@component}
        data-wotex-island-snapshot={@encoded}
        phx-hook="WotexLabSvelteIsland"
        phx-update="ignore"
      >
      </div>
    </section>
    """
  end

  @doc "Builds a stable island identifier scoped to one signed browser session."
  @spec id(String.t(), String.t()) :: String.t()
  def id("session-" <> _ = session_id, local_id)
      when is_binary(local_id) and byte_size(local_id) in 1..128 do
    session_id <> "--" <> local_id
  end

  @doc "Projects a renderer-neutral Workbench chart into the registered public prop schema."
  @spec chart_props(Chart.t()) :: map()
  def chart_props(%Chart{} = chart) do
    series =
      chart.series
      |> Enum.with_index()
      |> Enum.map(fn {item, index} ->
        %{"id" => "series-#{index}", "label" => item.name}
      end)

    indexed =
      chart.series
      |> Enum.with_index()
      |> Enum.map(fn {item, index} ->
        {"series-#{index}", Map.new(item.points)}
      end)

    points =
      chart.series
      |> Enum.flat_map(& &1.points)
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.with_index()
      |> Enum.map(fn {x, index} ->
        %{
          "key" => "point-#{index}",
          "label" => to_string(x),
          "values" => Map.new(indexed, fn {id, values} -> {id, Map.get(values, x)} end)
        }
      end)

    %{"title" => chart.title, "series" => series, "points" => points}
  end

  @doc "Projects bounded rows and columns into the registered data-grid prop schema."
  @spec data_grid_props(String.t(), [map()], [map()]) :: map()
  def data_grid_props(label, columns, rows) do
    %{
      "label" => label,
      "columns" => Enum.map(columns, &stringify_item/1),
      "rows" => Enum.map(rows, &stringify_item/1)
    }
  end

  @doc "Projects finite local tab content into the registered tabs prop schema."
  @spec tabs_props(String.t(), [map()], String.t()) :: map()
  def tabs_props(label, tabs, selected) do
    %{
      "label" => label,
      "tabs" => Enum.map(tabs, &stringify_item/1),
      "selected" => selected
    }
  end

  @doc "Builds a full-state protocol envelope for reconnect or explicit resynchronization."
  @spec snapshot(descriptor(), non_neg_integer()) :: {:ok, map()} | {:error, term()}
  def snapshot(%{component: component, id: id, props: props}, revision) do
    case Snapshot.new(component, id, props, generation: "0", revision: to_string(revision)) do
      {:ok, snapshot} -> {:ok, Map.from_struct(snapshot)}
      {:error, _} = error -> error
    end
  end

  @doc "Validates a client event through the Wotex Lab descriptor."
  @spec validate_event(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def validate_event(component, instance_id, payload),
    do: Event.validate(component, instance_id, payload)

  defp stringify_item(item) when is_map(item),
    do: Map.new(item, fn {key, value} -> {to_string(key), value} end)
end
