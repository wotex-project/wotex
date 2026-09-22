defmodule Wotex.Lab.Island.Component do
  @moduledoc """
  Closed browser contracts for the Lab's chart, data-grid and tabs islands.

  The descriptors name only public presentation props and admitted events.
  They contain no host module, route, credential or dynamic import path.
  """

  @components [
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
