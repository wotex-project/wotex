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
      |> assign_new(:theme, fn -> :system end)
      |> assign_new(:generation, fn ->
        to_string(System.unique_integer([:positive, :monotonic]))
      end)
      |> assign_new(:commands, fn -> [] end)
      |> assign(:contract, DesignContract.current())
      |> assign_fixture(assigns.fixture_id)

    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("advance", _, socket) do
    {:noreply, update(socket, :revision, &(&1 + 1))}
  end

  def handle_event("wotex:island:" <> _, _, %{assigns: %{fixture_error: true}} = socket) do
    {:reply, %{"status" => "rejected"}, socket}
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
      data-wotex-theme={@theme || :system}
      data-wotex-design-system={@contract["schema_version"]}
      data-wotex-token-digest={@contract["token_digest"]}
      data-wotex-component-digest={@contract["component_registry_digest"]}
      data-wotex-fixture-digest={@contract["story_fixture_digest"]}
      data-wotex-stylesheet-digest={@contract["stylesheet_digest"]}
      data-fixture-id={@fixture_id}
      data-fixture-payload-digest={@fixture_digest}
      data-server-revision={@revision}
    >
      <header>
        <p>LiveView transport revision <strong>{@revision}</strong></p>
        <button type="button" phx-click="advance" phx-target={@myself}>
          Advance server revision
        </button>
      </header>

      <p :if={@fixture_error} role="alert">
        Story fixture unavailable. Regenerate the Mix seed output.
      </p>

      <Island.island
        :if={!@fixture_error}
        id={"storybook--#{@fixture_id}"}
        component={@component}
        props={@props}
        generation={@generation}
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
            <th>Time</th><th :for={series <- @props["series"]}>{series["label"]}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={point <- @props["points"]}>
            <th>{point["label"]}</th>
            <td :for={series <- @props["series"]}>{point["values"][series["id"]]}</td>
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
          <th :for={column <- @props["columns"]}>{column["label"]}</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @props["rows"]}>
          <td :for={column <- @props["columns"]}>{row["values"][column["key"]]}</td>
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

  defp capabilities("reporting-chart"), do: ["inspect"]
  defp capabilities("data-grid"), do: ["select", "activate"]
  defp capabilities("navigation-tabs"), do: ["select"]

  defp assign_fixture(socket, id) do
    case DesignContract.fixture(id) do
      {:ok, snapshot} ->
        assign(socket,
          component: snapshot.component,
          props: snapshot.payload,
          fixture_digest: snapshot.payload_digest,
          fixture_error: false
        )

      {:error, _} ->
        assign(socket, component: nil, props: %{}, fixture_digest: nil, fixture_error: true)
    end
  end

  defp resync(socket, instance_id) do
    result =
      Snapshot.new(
        socket.assigns.component,
        instance_id,
        socket.assigns.props,
        generation: socket.assigns.generation,
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
           Event.validate(socket.assigns.component, instance_id, payload) do
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
