defmodule WotexContinuum.ThingReferenceTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.ThingDescription
  alias WotexContinuum.{ActionIntent, Error, ThingReference}

  test "delegates Thing Description meaning to the Wotex core" do
    assert {:ok, thing_description} = ThingDescription.from_map(valid_td())
    assert {:ok, intent} = ActionIntent.new(valid_intent())
    assert :ok = ThingReference.validate(intent, thing_description)

    assert {:ok, changed} = ThingDescription.put_id(thing_description, "urn:example:thing:other")

    assert {:error, %Error{code: :thing_id_mismatch}} =
             ThingReference.validate(intent, changed)
  end

  test "requires both a typed value reference and a Thing Description ID" do
    without_id = Map.delete(valid_td(), "id")
    assert {:ok, thing_description} = ThingDescription.from_map(without_id)
    assert {:ok, intent} = ActionIntent.new(valid_intent())

    assert {:error, %Error{code: :thing_id_required}} =
             ThingReference.validate(intent, thing_description)

    assert {:error, %Error{code: :thing_id_required}} =
             ThingReference.validate(%{}, thing_description)

    assert {:error, %Error{code: :invalid_type}} = ThingReference.validate(intent, %{})

    invalid = Map.put(valid_td(), "@context", "https://www.w3.org/2019/wot/td/v1")
    assert {:ok, unchecked} = ThingDescription.from_map(invalid, validate: false)

    assert {:error, %Error{code: :invalid_thing_description}} =
             ThingReference.validate(intent, unchecked)
  end

  defp valid_td do
    %{
      "@context" => Wotex.td_context_1_1(),
      "id" => "urn:example:thing:pump-7",
      "title" => "Example Pump",
      "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
      "security" => ["nosec_sc"],
      "actions" => %{
        "setLevel" => %{
          "input" => %{"type" => "object"},
          "forms" => [
            %{
              "href" => "https://example.test/pumps/7/actions/setLevel",
              "op" => "invokeaction"
            }
          ]
        }
      }
    }
  end

  defp valid_intent do
    %{
      intent_id: "intent-example-1",
      thing_id: "urn:example:thing:pump-7",
      action_name: "setLevel",
      input: %{"level" => 42},
      requested_at: "2026-09-02T10:00:00Z",
      idempotency_key: "intent-example-1",
      context: %{
        execution_id: "exec-example-1",
        node_id: "edge-example-a",
        mode: %{deployment: :connected_onprem, connectivity: :connected},
        observed_at: "2026-09-02T10:00:00Z"
      }
    }
  end
end
