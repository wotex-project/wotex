defmodule Wotex.Directory.InternalContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Directory.{Error, Fixtures, MergePatch, Registration, ThingDescriptions}

  @now ~U[2026-09-02 10:00:00Z]

  test "Thing Description boundary rejects non-values and malformed enriched maps" do
    assert {:error, %Error{code: :invalid_thing_description}} =
             ThingDescriptions.normalize_and_extract(%{}, [], :register)

    assert {:error, %Error{code: :invalid_thing_description}} =
             ThingDescriptions.from_enriched_map(%{"registration" => []}, [], :patch)

    assert {:error, %Error{code: :invalid_thing_description}} =
             ThingDescriptions.from_enriched_map(%{}, [], :patch)

    assert {:error, %Error{code: :invalid_thing_description}} =
             ThingDescriptions.from_enriched_map(
               %{
                 "@context" => [
                   Wotex.td_context_1_1(),
                   "https://www.w3.org/2022/wot/discovery"
                 ],
                 "registration" => %{}
               },
               [],
               :patch
             )
  end

  test "registration validates raw map shape, RFC 3339 time, and patch values" do
    assert {:error, %Error{code: :invalid_request}} =
             Registration.create(:not_a_datetime, :absent, :register)

    assert {:error, %Error{code: :invalid_request}} =
             Registration.create(@now, {:present, %{atom_key: true}}, :register)

    assert {:error, %Error{code: :invalid_request}} =
             Registration.create(@now, {:present, %{"expires" => "not-a-time"}}, :register)

    assert {:error, %Error{code: :invalid_request}} =
             Registration.create(@now, {:present, []}, :register)

    assert {:ok, initial} = Registration.create(@now, :absent, :register)

    assert {:error, %Error{code: :invalid_request}} =
             Registration.refresh(initial, @now, :invalid, :replace)

    assert {:error, %Error{code: :invalid_request}} =
             Registration.refresh(:not_registration, @now, :absent, :replace)

    assert {:error, %Error{code: :invalid_request}} =
             Registration.from_patch(initial, @now, :invalid, :patch)

    assert Registration.server_field_patch?(:invalid) == false
  end

  test "merge patch accepts every JSON value class and rejects invalid limits and values" do
    patch = %{
      "array" => [1, 2.5, true, false, nil, "value"],
      "object" => %{"nested" => 1}
    }

    assert {:ok, ^patch} = MergePatch.apply(%{}, patch)
    assert {:error, :invalid_json_value} = MergePatch.apply(%{}, patch, maximum_depth: 0)
    assert {:error, :invalid_json_value} = MergePatch.apply(%{}, patch, maximum_nodes: 0)
    assert {:error, :invalid_json_value} = MergePatch.apply(%{}, patch, :not_options)
    assert {:error, :invalid_json_value} = MergePatch.apply(%{}, patch, unknown: 1)
    assert {:error, :invalid_json_value} = MergePatch.apply(%{}, %{"tuple" => {:not, :json}})
  end

  test "enriched output preserves an existing Discovery context exactly once" do
    thing_description =
      Fixtures.thing_description("urn:example:thing:1", %{
        "@context" => [
          Wotex.td_context_1_1(),
          "https://www.w3.org/2022/wot/discovery"
        ]
      })

    assert {:ok, registration} = Registration.create(@now, :absent, :register)
    map = ThingDescriptions.enriched_map(thing_description, registration)

    assert Enum.count(map["@context"], &(&1 == "https://www.w3.org/2022/wot/discovery")) == 1
  end
end
