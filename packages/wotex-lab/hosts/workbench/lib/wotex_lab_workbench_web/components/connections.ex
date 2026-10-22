defmodule WotexLabWorkbenchWeb.Components.Connections do
  @moduledoc "Compact connection list and editor for the existing reference room."

  use WotexLabWorkbenchWeb, :html

  alias Phoenix.LiveView.JS
  alias WotexLabWorkbench.{Canvas, Connections, ThingProperties, ThingReadings}

  attr(:room, :any, required: true)
  attr(:model, :map, required: true)
  attr(:things, :list, required: true)
  attr(:readings, :map, required: true)
  attr(:observations, :map, required: true)
  attr(:draft, :any, required: true)
  attr(:error, :any, required: true)
  attr(:focus_port, :string, default: nil)

  @doc "Renders current bindings or one retained, uncommitted connection draft."
  @spec connections_view(map()) :: Phoenix.LiveView.Rendered.t()
  def connections_view(assigns) do
    options =
      if assigns.draft, do: Connections.options(assigns.things, assigns.draft["port"]), else: []

    selected = assigns.draft && Enum.find(options, &matches?(&1, assigns.draft))
    source = selected && Enum.find(assigns.things, &(&1.key == selected.thing))
    reading = selected && ThingReadings.get(assigns.readings, selected.thing, selected.affordance)

    assigns =
      assign(assigns,
        rows: rows(assigns),
        options: options,
        choices: Enum.uniq_by(options, & &1.thing),
        affordances: Enum.filter(options, &(assigns.draft && &1.thing == assigns.draft["thing"])),
        selected: selected,
        source: source,
        reading: reading,
        observable: observable?(source, selected),
        watching:
          selected &&
            Map.has_key?(assigns.observations, selected.thing <> "/" <> selected.affordance),
        forms: forms(source, selected)
      )

    ~H"""
    <div :if={is_nil(@room)}>
      <button type="button" phx-click="start_room" class="wl-button wl-button-primary">Start room</button>
    </div>
    <div
      :if={@room && is_nil(@draft)}
      id="wl-connections-list"
      class="wl-connections-list"
      phx-mounted={
        if @focus_port in Connections.ports(),
          do: JS.focus(to: "#wl-connection-#{@focus_port}"),
          else: JS.focus_first(to: "#wl-connections-list")
      }
    >
      <section :for={row <- @rows} class="wl-connection-row" aria-label={row.title}>
        <header>
          <h3>{row.title}</h3>
          <button
            id={"wl-connection-#{row.port}"}
            class="wl-button wl-button-secondary"
            type="button"
            phx-click="edit_connection"
            phx-value-port={row.port}
            aria-label={"#{if row.binding, do: "Change", else: "Connect"} #{row.title}"}
          >{if row.binding, do: "Change", else: "Connect"}</button>
        </header>
        <p class="wl-connection-endpoints">{row.label}</p>
        <div :if={row.reading} class="wl-connection-reading">
          <strong>{row.reading.value}</strong><span>{row.unit}</span>
          <span class="wl-muted">{ThingReadings.status(row.reading)}</span>
        </div>
      </section>
    </div>
    <div
      :if={@room && @draft}
      id="wl-connection-editor"
      class="wl-stack"
      phx-mounted={JS.focus(to: "#wl-connection-thing")}
    >
      <form
        id="wl-connection-form"
        phx-change="change_connection"
        phx-submit="apply_connection"
        phx-auto-recover="change_connection"
        class="wl-stack"
      >
        <input type="hidden" name="connection[port]" value={@draft["port"]} />
        <input type="hidden" name="connection[revision]" value={@draft["revision"]} />
        <div class="wl-field">
          <label for="wl-connection-thing">{if @draft["port"] == "proposal",
            do: "Target",
            else: "Source"}</label>
          <select id="wl-connection-thing" name="connection[thing]" required>
            <option
              :if={not Enum.any?(@choices, &(&1.thing == @draft["thing"]))}
              value={@draft["thing"]}
              selected
              disabled
            >
              {if @draft["thing"] == "", do: "Choose a Thing", else: "Unavailable"}
            </option>
            <option
              :for={choice <- @choices}
              value={choice.thing}
              selected={choice.thing == @draft["thing"]}
            >
              {thing_title(@things, choice.thing)}
            </option>
          </select>
        </div>
        <div class="wl-field">
          <label for="wl-connection-affordance">{if @draft["port"] == "proposal",
            do: "Action",
            else: "Property"}</label>
          <select id="wl-connection-affordance" name="connection[affordance]" required>
            <option
              :if={not Enum.any?(@affordances, &(&1.affordance == @draft["affordance"]))}
              value={@draft["affordance"]}
              selected
              disabled
            >
              {if @draft["affordance"] == "", do: "Choose an affordance", else: "Unavailable"}
            </option>
            <option
              :for={option <- @affordances}
              value={option.affordance}
              selected={option.affordance == @draft["affordance"]}
            >
              {option.affordance} · {unit(option.unit)}
            </option>
          </select>
        </div>
        <div :if={@error} role="alert" class="wl-connection-error">
          <p>{@error.message}</p>
          <button
            :if={@error.code == :stale_connection}
            class="wl-button wl-button-secondary"
            type="button"
            phx-click={JS.push("reload_connection") |> JS.focus(to: "#wl-connection-thing")}
            phx-value-port={@draft["port"]}
          >Reload draft</button>
        </div>
        <div class="wl-actions">
          <button type="submit" class="wl-button wl-button-primary">Apply</button>
          <button class="wl-button wl-button-secondary" type="button" phx-click="cancel_connection">Cancel</button>
          <button
            :if={@model.bindings[@draft["port"]]}
            class="wl-button wl-button-secondary"
            type="button"
            phx-click="remove_connection"
            phx-value-port={@draft["port"]}
            phx-value-revision={@draft["revision"]}
          >Remove</button>
        </div>
      </form>
      <section
        :if={@selected && @selected.kind == :property}
        class="wl-connection-receipt"
        aria-label="Source Property"
      >
        <div class="wl-connection-reading">
          <strong>{if @reading, do: @reading.value, else: "—"}</strong>
          <span>{unit(@selected.unit)}</span>
          <span class="wl-muted">{if @reading, do: ThingReadings.status(@reading), else: "Not read"}</span>
        </div>
        <time :if={@reading} datetime={@reading.read_at} class="wl-muted">{ThingReadings.time(@reading)}</time>
        <div class="wl-actions">
          <button
            class="wl-button wl-button-secondary"
            type="button"
            phx-click="read"
            phx-value-thing={@selected.thing}
            phx-value-property={@selected.affordance}
          >Read {@selected.affordance}</button>
          <button
            :if={@observable}
            class="wl-button wl-button-secondary"
            type="button"
            phx-click={if @watching, do: "pause_observation", else: "observe"}
            phx-value-thing={@selected.thing}
            phx-value-property={@selected.affordance}
          >{if @watching, do: "Pause", else: "Observe"}</button>
        </div>
      </section>
      <details :if={@selected} class="wl-disclosure">
        <summary>Sources</summary>
        <dl class="wl-meta-list">
          <dt>Thing ID</dt><dd>{@selected.thing_id}</dd>
          <dt>Affordance</dt><dd>{@selected.affordance}</dd>
          <dt>Data schema</dt><dd>{@selected.schema["type"]} · {@selected.unit}</dd>
          <dt>Declared Forms</dt><dd :for={form <- @forms}>{form["href"]}</dd>
          <dt>Connection revision</dt><dd>{@model.revision}</dd>
        </dl>
      </details>
    </div>
    """
  end

  defp rows(assigns) do
    Enum.map(Connections.ports(), fn port ->
      binding =
        case Connections.fetch(assigns.model, assigns.things, port) do
          {:ok, option} -> option
          _ -> nil
        end

      label =
        cond do
          is_nil(binding) ->
            "Not connected"

          port == "proposal" ->
            "Smart room → " <>
              thing_title(assigns.things, binding.thing) <> " · " <> binding.affordance

          true ->
            thing_title(assigns.things, binding.thing) <>
              " · " <> binding.affordance <> " → Smart room"
        end

      %{
        port: port,
        title: Connections.title(port),
        binding: binding,
        label: label,
        unit: binding && unit(binding.unit),
        reading:
          binding && binding.kind == :property &&
            ThingReadings.get(assigns.readings, binding.thing, binding.affordance)
      }
    end)
  end

  defp thing_title(things, key) do
    things
    |> Enum.find(&(&1.key == key))
    |> Canvas.title()
  end

  defp unit("Cel"), do: "°C"
  defp unit(value), do: value

  defp matches?(option, raw),
    do: option.thing == raw["thing"] and option.affordance == raw["affordance"]

  defp observable?(nil, _), do: false
  defp observable?(_, nil), do: false

  defp observable?(thing, option),
    do: Enum.any?(ThingProperties.rows(thing), &(&1.name == option.affordance and &1.observable))

  defp forms(nil, _), do: []
  defp forms(_, nil), do: []

  defp forms(thing, option) do
    group = if option.kind == :action, do: "actions", else: "properties"
    get_in(thing.document, [group, option.affordance, "forms"]) || []
  end
end
