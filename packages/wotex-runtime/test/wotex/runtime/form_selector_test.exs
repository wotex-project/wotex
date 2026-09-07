defmodule Wotex.Runtime.FormSelectorTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Runtime.{Error, FormSelector}
  alias Wotex.Runtime.Test.TDFactory

  test "TD Form order takes precedence and relative href resolves against base" do
    td = TDFactory.thing_description()

    assert {:ok, selection} =
             FormSelector.select(
               td,
               :property,
               "temperature",
               :readproperty,
               [TDFactory.mqtt_profile(), TDFactory.http_profile()]
             )

    assert selection.profile.id == :http

    assert selection.resolved_href ==
             "https://example.test/machines/1/properties/temperature"

    assert selection.security == %{
             names: ["nosec_sc"],
             definitions: %{"nosec_sc" => %{"scheme" => "nosec"}}
           }
  end

  test "profile order breaks ties within one Form" do
    td = TDFactory.thing_description()
    first = TDFactory.http_profile(id: :first)
    second = TDFactory.http_profile(id: :second)

    assert {:ok, selection} =
             FormSelector.select(td, :action, "calibrate", :invokeaction, [second, first])

    assert selection.profile.id == :second
  end

  test "selects only exact Thing-level operations from top-level Forms" do
    td = TDFactory.thing_description()

    assert {:ok, selection} =
             FormSelector.select_thing(td, :readallproperties, [TDFactory.http_profile()])

    assert selection.affordance_type == :thing
    assert selection.affordance_name == nil
    assert selection.operation == :readallproperties
    assert selection.resolved_href == "https://example.test/machines/1/interactions"

    assert {:error, %Error{code: :unsupported_operation}} =
             FormSelector.select_thing(td, :readproperty, [TDFactory.http_profile()])
  end

  test "selects absolute mqtt Form when the operation is not present on the first Form" do
    map =
      TDFactory.thing_description()
      |> Wotex.ThingDescription.to_map()
      |> put_in(
        ["properties", "temperature", "forms", Access.at(0), "op"],
        ["writeproperty"]
      )

    {:ok, td} = Wotex.ThingDescription.from_map(map)

    assert {:ok, selection} =
             FormSelector.select(
               td,
               :property,
               "temperature",
               :readproperty,
               [TDFactory.http_profile(), TDFactory.mqtt_profile()]
             )

    assert selection.profile.id == :mqtt
    assert selection.resolved_href == "mqtt://broker.example.test/machine/temperature"
  end

  test "returns stable absence for missing affordances and incompatible cells" do
    td = TDFactory.thing_description()

    assert {:error, %Error{code: :affordance_not_found}} =
             FormSelector.select(td, :event, "missing", :subscribeevent, [TDFactory.http_profile()])

    profile = TDFactory.http_profile(operations: [:readproperty])

    assert {:error, %Error{code: :compatible_form_not_found}} =
             FormSelector.select(td, :action, "calibrate", :invokeaction, [profile])

    assert {:error, %Error{code: :unsupported_operation}} =
             FormSelector.select(td, :property, "temperature", :invented, [profile])

    assert {:error, %Error{code: :invalid_selection_input}} =
             FormSelector.select(td, :unknown, "temperature", :readproperty, [profile])
  end

  test "applies TD 1.1 default operations when Form op is absent" do
    map =
      TDFactory.thing_description()
      |> Wotex.ThingDescription.to_map()
      |> update_in(["actions", "calibrate", "forms"], fn [form] -> [Map.delete(form, "op")] end)
      |> update_in(["properties", "temperature", "forms"], fn [form | _rest] ->
        [Map.delete(form, "op")]
      end)
      |> put_in(["properties", "temperature", "readOnly"], true)
      |> update_in(["events", "alarm", "forms"], fn [form] -> [Map.delete(form, "op")] end)

    {:ok, td} = Wotex.ThingDescription.from_map(map)
    profiles = [TDFactory.http_profile()]

    assert {:ok, %{operation: :invokeaction}} =
             FormSelector.select(td, :action, "calibrate", :invokeaction, profiles)

    assert {:error, %Error{code: :compatible_form_not_found}} =
             FormSelector.select(td, :action, "calibrate", :queryaction, profiles)

    assert {:ok, %{operation: :readproperty}} =
             FormSelector.select(td, :property, "temperature", :readproperty, profiles)

    assert {:error, %Error{code: :compatible_form_not_found}} =
             FormSelector.select(td, :property, "temperature", :writeproperty, profiles)

    assert {:error, %Error{code: :compatible_form_not_found}} =
             FormSelector.select(td, :property, "temperature", :observeproperty, profiles)

    assert {:ok, %{operation: :subscribeevent}} =
             FormSelector.select(td, :event, "alarm", :subscribeevent, profiles)
  end

  test "thing-level Forms receive no default operations" do
    map =
      TDFactory.thing_description()
      |> Wotex.ThingDescription.to_map()
      |> update_in(["forms"], fn [form] -> [Map.delete(form, "op")] end)

    assert {:error, _errors} = Wotex.ThingDescription.from_map(map)
  end

  test "rejects malformed Forms and unresolved relative references" do
    malformed_map =
      TDFactory.thing_description()
      |> Wotex.ThingDescription.to_map()
      |> put_in(["properties", "temperature", "forms"], ["not-a-form"])

    {:ok, malformed} = Wotex.ThingDescription.from_map(malformed_map, validate: false)

    assert {:error, %Error{code: :compatible_form_not_found}} =
             FormSelector.select(
               malformed,
               :property,
               "temperature",
               :readproperty,
               [TDFactory.http_profile()]
             )

    relative_map =
      TDFactory.thing_description()
      |> Wotex.ThingDescription.to_map()
      |> Map.delete("base")
      |> put_in(["properties", "temperature", "forms"], [
        %{"href" => "properties/temperature", "op" => "readproperty"}
      ])

    {:ok, relative} = Wotex.ThingDescription.from_map(relative_map)

    assert {:error, %Error{code: :compatible_form_not_found}} =
             FormSelector.select(
               relative,
               :property,
               "temperature",
               :readproperty,
               [TDFactory.http_profile()]
             )
  end
end
