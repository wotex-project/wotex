defmodule WotexLabWorkbenchWeb.Components.BoardSearch do
  @moduledoc """
  A bounded, read-only index of the current canvas subjects and owned pins.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS
  alias WotexLabWorkbench.Canvas

  attr(:things, :list, required: true)
  attr(:runs, :list, required: true)
  attr(:readings, :map, required: true)
  attr(:connections, :map, required: true)
  attr(:board, :map, required: true)
  attr(:query, :string, required: true)
  attr(:error, :string, default: nil)
  attr(:focus_id, :string, default: nil)

  @doc "Renders a searchable list without reading a Property or querying a pin."
  @spec board_search(map()) :: Phoenix.LiveView.Rendered.t()
  def board_search(assigns) do
    nodes =
      Canvas.props(assigns.things, assigns.runs, assigns.readings, nil, assigns.connections)[
        "nodes"
      ]

    entries = Enum.map(nodes, &node_entry/1) ++ Enum.map(assigns.board.pins, &pin_entry/1)

    terms =
      assigns.query
      |> String.downcase()
      |> String.split()

    results =
      entries
      |> Enum.filter(fn entry ->
        text = String.downcase(Enum.join([entry.title, entry.detail, entry.kind], " "))
        Enum.all?(terms, &String.contains?(text, &1))
      end)
      |> Enum.sort_by(&{String.downcase(&1.title), &1.id})

    focus =
      if Enum.any?(results, &(&1.id == assigns.focus_id)),
        do: "#wl-search-result-#{assigns.focus_id}",
        else: "#wl-board-search-query"

    assigns = assign(assigns, results: results, total: length(entries), focus: focus)

    ~H"""
    <div
      id="wl-board-search-content"
      class="wl-stack"
      data-focus-target={@focus}
      phx-hook="WotexBoardSearch"
    >
      <form id="wl-board-search-form" phx-change="search_board" phx-submit="search_board">
        <label class="wl-sr-only" for="wl-board-search-query">Search board</label>
        <input
          id="wl-board-search-query"
          name="query"
          type="search"
          value={@query}
          maxlength="128"
          autocomplete="off"
          spellcheck="false"
          placeholder="Things, processes, pins…"
          aria-describedby="wl-board-search-count"
        />
        <button
          :if={@query != "" || @error}
          type="button"
          class="wl-panel-close"
          aria-label="Clear search"
          phx-click={
            JS.dispatch("wotex:clear-board-search")
            |> JS.push("clear_board_search")
          }
        ><img class="wl-menu-icon" src="/icons/x.svg" alt="" width="14" height="14" /></button>
      </form>
      <p :if={@error} role="alert" class="wl-connection-error">{@error}</p>
      <p id="wl-board-search-count" class="wl-muted" role="status" aria-live="polite">
        {length(@results)} {if length(@results) == 1, do: "result", else: "results"}
      </p>
      <ul id="wl-board-search-results" class="wl-board-search-results" aria-label="Board results">
        <li :for={entry <- @results}>
          <button
            id={"wl-search-result-#{entry.id}"}
            type="button"
            phx-click="inspect_board_result"
            phx-value-id={entry.id}
            aria-label={"Inspect #{entry.title}"}
          >
            <img class="wl-menu-icon" src={"/icons/#{entry.icon}.svg"} alt="" width="16" height="16" />
            <span><strong>{entry.title}</strong><small>{entry.detail}</small></span>
            <small>{entry.kind}</small>
          </button>
        </li>
      </ul>
      <p :if={@results == []} class="wl-muted">
        {if @total == 0, do: "Your board is empty", else: "No matches"}
      </p>
    </div>
    """
  end

  defp node_entry(node) do
    {kind, icon} =
      case node["kind"] do
        "process" -> {"Process", "flask-conical"}
        "entry" -> {"Directory entry", "book-open"}
        _ -> {"Thing", "waypoints"}
      end

    %{id: node["id"], title: node["title"], detail: node["identity"], kind: kind, icon: icon}
  end

  defp pin_entry(%{kind: :run} = pin) do
    %{
      id: pin.id,
      title: pin.title,
      detail: "#{pin.run_id} · #{pin.source_mode}",
      kind: "Run pin",
      icon: "chart-no-axes-combined"
    }
  end

  defp pin_entry(pin) do
    %{
      id: pin.id,
      title: pin.title,
      detail: "#{pin.metric} · Room history",
      kind: "Metric pin",
      icon: "chart-no-axes-combined"
    }
  end
end
