defmodule Wotex.Directory.EventTest do
  use ExUnit.Case, async: true

  alias Wotex.Directory.{Entry, Error, Event, Mutation, Registration}
  alias Wotex.Directory.Fixtures

  @now ~U[2026-09-05 10:00:00Z]
  @identifier "urn:example:thing:1"

  test "derives full creation data from a created registration" do
    mutation = mutation(:register, :created)

    assert {:ok, %Event{type: :thing_created, data: data}} =
             Event.from_mutation(mutation)

    assert data["id"] == @identifier
    assert data["registration"]["created"] == "2026-09-05T10:00:00Z"
  end

  test "maps every successful update outcome to thing_updated" do
    for {operation, status} <- [
          {:register, :replaced},
          {:replace, :replaced},
          {:patch, :patched}
        ] do
      assert {:ok, %Event{type: :thing_updated}} =
               operation
               |> mutation(status)
               |> Event.from_mutation()
    end
  end

  test "supports minimum Partial TD event data" do
    mutation = mutation(:replace, :replaced)

    assert {:ok, %Event{data: %{"id" => @identifier}}} =
             Event.from_mutation(mutation, payload: :identifier)
  end

  test "deletion never exposes a removed Thing Description" do
    mutation = mutation(:delete, :deleted)

    assert {:ok, %Event{type: :thing_deleted, data: %{"id" => @identifier}}} =
             Event.from_mutation(mutation, payload: :full)
  end

  test "rejects impossible mutation outcomes, malformed entries, and options" do
    valid = mutation(:replace, :replaced)
    impossible = %{valid | status: :created}
    malformed = %{valid | entry: %{valid.entry | identifier: "relative"}}

    for request <- [
          fn -> Event.from_mutation(impossible) end,
          fn -> Event.from_mutation(malformed) end,
          fn -> Event.from_mutation(valid, payload: :diff) end,
          fn -> Event.from_mutation(valid, unknown: true) end,
          fn -> Event.from_mutation(:not_a_mutation) end
        ] do
      assert {:error, %Error{code: :invalid_request, operation: :event}} = request.()
    end
  end

  defp mutation(operation, status) do
    {:ok, registration} = Registration.create(@now, :absent, :register)
    {:ok, entry} = Entry.new(@identifier, Fixtures.thing_description(@identifier), registration)

    %Mutation{operation: operation, status: status, entry: entry}
  end
end
