defmodule WotexLabStorybookWeb.IslandLive do
  @moduledoc "LiveView qualification wrapper for the three Wotex island fixtures."

  use Phoenix.LiveComponent

  alias Wotex.Lab.Island.{Event, Snapshot}
  alias WotexLabStorybook.DesignContract
  alias WotexLabStorybookWeb.Island

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:revision, fn -> 1 end)
      |> assign_new(:commands, fn -> [] end)
      |> assign(:contract, DesignContract.current())
      |> assign(:props, props(assigns.fixture_id))

    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("advance", _, socket) do
    {:noreply, update(socket, :revision, &(&1 + 1))}
  end

  def handle_event("wotex:island:" <> event, payload, socket) do
    instance_id = "storybook--#{socket.assigns.fixture_id}"

    cond do
      event == instance_id <> ":resync" ->
        resync(socket, instance_id)

      event == instance_id <> ":event" ->
        admit_event(socket, instance_id, payload)

      true ->
        {:reply, %{"status" => "rejected"}, socket}
    end
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <section
      class="wotex-lab"
      data-wotex-design-system={@contract["schema_version"]}
      data-wotex-token-digest={@contract["token_digest"]}
      data-wotex-component-digest={@contract["component_registry_digest"]}
      data-wotex-fixture-digest={@contract["story_fixture_digest"]}
      data-wotex-stylesheet-digest={@contract["stylesheet_digest"]}
      data-fixture-id={@fixture_id}
      data-server-revision={@revision}
    >
      <header>
        <p>LiveView transport revision <strong>{@revision}</strong></p>
        <button type="button" phx-click="advance" phx-target={@myself}>
          Advance server revision
        </button>
      </header>

      <Island.island
        id={"storybook--#{@fixture_id}"}
        component={component(@fixture_id)}
        props={@props}
        generation="0"
        revision={to_string(@revision)}
        capabilities={capabilities(@fixture_id)}
        target={@myself}
      >
        <:fallback>
          <.fallback fixture_id={@fixture_id} props={@props} />
        </:fallback>
      </Island.island>
    </section>
    """
  end

  attr(:fixture_id, :string, required: true)
  attr(:props, :map, required: true)

  defp fallback(%{fixture_id: "reporting-chart"} = assigns) do
    ~H"""
    <figure data-semantic-fallback="reporting-chart">
      <figcaption>{@props["title"]}</figcaption>
      <table>
        <thead>
          <tr>
            <th>Time</th><th>Temperature</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={point <- @props["points"]}>
            <th>{point["label"]}</th><td>{point["values"]["temperature"]}</td>
          </tr>
        </tbody>
      </table>
    </figure>
    """
  end

  defp fallback(%{fixture_id: "data-grid"} = assigns) do
    ~H"""
    <table data-semantic-fallback="data-grid">
      <caption>{@props["label"]}</caption>
      <thead>
        <tr>
          <th>Thing</th><th>Status</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @props["rows"]}>
          <th>{row["values"]["name"]}</th><td>{row["values"]["status"]}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp fallback(%{fixture_id: "navigation-tabs"} = assigns) do
    ~H"""
    <section data-semantic-fallback="navigation-tabs" aria-label={@props["label"]}>
      <article :for={tab <- @props["tabs"]}>
        <h3>{tab["label"]}</h3>
        <p>{tab["content"]}</p>
      </article>
    </section>
    """
  end

  defp component("reporting-chart"), do: "chart"
  defp component("data-grid"), do: "data-grid"
  defp component("navigation-tabs"), do: "tabs"

  defp capabilities("reporting-chart"), do: ["inspect"]
  defp capabilities("data-grid"), do: ["select", "activate"]
  defp capabilities("navigation-tabs"), do: ["select"]

  defp props("reporting-chart") do
    %{
      "title" => "Room temperature",
      "series" => [%{"id" => "temperature", "label" => "Temperature"}],
      "points" => [
        %{"key" => "09:00", "label" => "09:00", "values" => %{"temperature" => 21.2}},
        %{"key" => "10:00", "label" => "10:00", "values" => %{"temperature" => 21.6}},
        %{"key" => "11:00", "label" => "11:00", "values" => %{"temperature" => 22.0}}
      ]
    }
  end

  defp props("data-grid") do
    %{
      "label" => "Observed Things",
      "columns" => [
        %{"key" => "name", "label" => "Thing"},
        %{"key" => "status", "label" => "Status"}
      ],
      "rows" => [
        %{
          "key" => "sensor-1",
          "values" => %{"name" => "Meeting room", "status" => "Online"}
        },
        %{"key" => "sensor-2", "values" => %{"name" => "Workshop", "status" => "Offline"}}
      ]
    }
  end

  defp props("navigation-tabs") do
    %{
      "label" => "Thing details",
      "selected" => "properties",
      "tabs" => [
        %{"id" => "properties", "label" => "Properties", "content" => "Three readable values"},
        %{"id" => "actions", "label" => "Actions", "content" => "One safe action"}
      ]
    }
  end

  defp resync(socket, instance_id) do
    result =
      Snapshot.new(
        component(socket.assigns.fixture_id),
        instance_id,
        socket.assigns.props,
        generation: "0",
        revision: to_string(socket.assigns.revision),
        capabilities: capabilities(socket.assigns.fixture_id)
      )

    case result do
      {:ok, snapshot} ->
        {:noreply,
         Phoenix.LiveView.push_event(
           socket,
           "wotex:island:#{instance_id}:snapshot",
           Map.from_struct(snapshot)
         )}

      _ ->
        {:reply, %{"status" => "rejected"}, socket}
    end
  end

  defp admit_event(socket, instance_id, payload) do
    with true <- payload["client_revision"] == to_string(socket.assigns.revision),
         {:ok, event} <-
           Event.validate(component(socket.assigns.fixture_id), instance_id, payload) do
      acknowledge(socket, event["command_id"])
    else
      _ -> {:reply, %{"status" => "rejected"}, socket}
    end
  end

  defp acknowledge(socket, nil), do: {:reply, %{"status" => "accepted"}, socket}

  defp acknowledge(socket, command_id) do
    if command_id in socket.assigns.commands do
      {:reply, %{"status" => "duplicate"}, socket}
    else
      {:reply, %{"status" => "accepted"},
       assign(socket, :commands, Enum.take([command_id | socket.assigns.commands], 64))}
    end
  end
end
