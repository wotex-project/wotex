defmodule Wotex.Lab.Island.Component do
  @moduledoc """
  Closed browser contracts for the Lab's chart, data-grid, tabs and canvas islands.

  The descriptors name only public presentation props and admitted events.
  They contain no host module, route, credential or dynamic import path.
  """

  @components [
    %{
      "id" => "canvas",
      "story_id" => "connected-things",
      "states" => ~w(default empty selected disconnected),
      "fallback" => "labelled Thing list and explicit Property read forms",
      "props" => %{
        "label" => %{"type" => "string", "required" => true, "max_bytes" => 256},
        "nodes" => %{"type" => "item_list", "required" => true, "max_items" => 32},
        "edges" => %{"type" => "item_list", "required" => true, "max_items" => 64},
        "pins" => %{"type" => "item_list", "max_items" => 16},
        "view" => %{"type" => "item_list", "max_items" => 1},
        "layout_revision" => %{"type" => "string", "max_bytes" => 32},
        "selection" => %{"type" => "string", "max_bytes" => 128}
      },
      "events" => %{
        "inspect" => %{"payload" => "id", "effectful" => false},
        "inspect_connection" => %{"payload" => "id", "effectful" => false},
        "propose_connection" => %{"payload" => "connection", "effectful" => false},
        "open" => %{"payload" => "id", "effectful" => false},
        "read" => %{"payload" => "id", "effectful" => false},
        "observe" => %{"payload" => "id", "effectful" => false},
        "pause" => %{"payload" => "id", "effectful" => false},
        "statistics" => %{"payload" => "id", "effectful" => false},
        "sources" => %{"payload" => "id", "effectful" => false},
        "save_layout" => %{"payload" => "layout", "effectful" => false},
        "open_documentation" => %{"payload" => "view", "effectful" => false},
        "pin_refresh" => %{"payload" => "id", "effectful" => false},
        "pin_pause" => %{"payload" => "id", "effectful" => false},
        "pin_resume" => %{"payload" => "id", "effectful" => false},
        "pin_remove" => %{"payload" => "id", "effectful" => false}
      }
    },
    %{
      "id" => "chart",
      "story_id" => "reporting-chart",
      "states" => ~w(default loading empty error disconnected),
      "fallback" => "summary and data table",
      "props" => %{
        "title" => %{"type" => "string", "required" => true, "max_bytes" => 256},
        "series" => %{"type" => "item_list", "required" => true, "max_items" => 8},
        "points" => %{"type" => "item_list", "required" => true, "max_items" => 2_000}
      },
      "events" => %{"inspect" => %{"payload" => "key", "effectful" => false}}
    },
    %{
      "id" => "data-grid",
      "story_id" => "data-grid",
      "states" => ~w(default selected loading empty error disconnected),
      "fallback" => "semantic table",
      "props" => %{
        "label" => %{"type" => "string", "required" => true, "max_bytes" => 256},
        "columns" => %{"type" => "item_list", "required" => true, "max_items" => 64},
        "rows" => %{"type" => "item_list", "required" => true, "max_items" => 2_000}
      },
      "events" => %{
        "select" => %{"payload" => "key", "effectful" => false},
        "activate" => %{"payload" => "key", "effectful" => true}
      }
    },
    %{
      "id" => "tabs",
      "story_id" => "navigation-tabs",
      "states" => ~w(default selected disabled disconnected),
      "fallback" => "stacked labelled sections",
      "props" => %{
        "label" => %{"type" => "string", "required" => true, "max_bytes" => 256},
        "tabs" => %{"type" => "item_list", "required" => true, "max_items" => 32},
        "selected" => %{"type" => "string", "max_bytes" => 256}
      },
      "events" => %{"select" => %{"payload" => "id", "effectful" => false}}
    }
  ]

  @doc "Returns the descriptor digest used by Lab hosts and evidence."
  @spec digest() :: String.t()
  def digest do
    {:ok, bytes} = Wotex.JSON.encode(@components)
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  end

  @doc "Returns every admitted island descriptor."
  @spec all() :: [map()]
  def all, do: @components

  @doc "Fetches a descriptor by its stable component identifier."
  @spec fetch(String.t()) :: {:ok, map()} | :error
  def fetch(id) when is_binary(id) do
    case Enum.find(@components, &(&1["id"] == id)) do
      nil -> :error
      component -> {:ok, component}
    end
  end

  def fetch(_), do: :error
end
