defmodule WotexLabWorkbenchWeb.Islands do
  @moduledoc """
  Closed Workbench projections for the registered Phoenix Assets islands.

  The functions in this module expose only bounded presentation data. The
  surrounding LiveView retains the session, room, run, query and command
  identities, while each island keeps its semantic HEEx fallback beside the
  ignored Svelte mount root.
  """

  use Phoenix.Component

  alias WotexLabWorkbench.Chart

  @type descriptor :: %{component: String.t(), id: String.t(), props: map()}

  attr :id, :string, required: true
  attr :chart, :any, required: true
  attr :revision, :integer, required: true
  slot :fallback, required: true

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

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :columns, :list, required: true
  attr :rows, :list, required: true
  attr :revision, :integer, required: true
  slot :fallback, required: true

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

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :tabs, :list, required: true
  attr :selected, :string, required: true
  attr :revision, :integer, required: true
  slot :fallback, required: true

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

  attr :id, :string, required: true
  attr :component, :string, required: true
  attr :props, :map, required: true
  attr :generation, :string, required: true
  attr :revision, :string, required: true
  attr :capabilities, :list, required: true
  slot :fallback, required: true

  if Code.ensure_loaded?(PhoenixAssets.Svelte.Island) do
    alias PhoenixAssets.Svelte.Island

    defp island_boundary(assigns) do
      ~H"""
      <Island.island
        id={@id}
        component={@component}
        props={@props}
        generation={@generation}
        revision={@revision}
        capabilities={@capabilities}
      >
        <:fallback>{render_slot(@fallback)}</:fallback>
      </Island.island>
      """
    end
  else
    defp island_boundary(assigns) do
      ~H"""
      {render_slot(@fallback)}
      """
    end
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
    module = PhoenixAssets.Svelte.Island.Snapshot

    if Code.ensure_loaded?(module) do
      case module.new(
             component,
             id,
             props,
             generation: "0",
             revision: to_string(revision)
           ) do
        {:ok, snapshot} -> {:ok, Map.from_struct(snapshot)}
        {:error, _} = error -> error
      end
    else
      {:error, :island_artifact_unavailable}
    end
  end

  @doc "Validates a client event through the adopted Phoenix Assets descriptor."
  @spec validate_event(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def validate_event(component, instance_id, payload) do
    module = PhoenixAssets.Svelte.Island.Event

    if Code.ensure_loaded?(module),
      do: module.validate(component, instance_id, payload),
      else: {:error, :island_artifact_unavailable}
  end

  defp stringify_item(item) when is_map(item),
    do: Map.new(item, fn {key, value} -> {to_string(key), value} end)
end
