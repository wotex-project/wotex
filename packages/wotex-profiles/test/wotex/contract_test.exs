defmodule Wotex.Profiles.ContractTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Profiles.{Artifacts, AuthoringLimits, Contract, Error}
  alias Wotex.Profiles.Test.Fixtures, as: F

  defp contract do
    Contract.export(
      [F.json("installed-binding")],
      F.json("installed-contracts"),
      F.json("authoring-limits"),
      Artifacts.current()
    )
  end

  test "installed export, native revalidation and serialized round trip share one identity" do
    assert {:ok, value} = contract()
    assert {:ok, ^value} = Contract.new(value)
    assert {:ok, bytes} = Contract.encode(value)
    assert {:ok, ^value} = Contract.parse(bytes)
    assert {:ok, digest} = Contract.identity(value)

    assert digest ==
             Base.encode16(:crypto.hash(:sha256, "wotex.profile.authoring-contract@1\n" <> bytes),
               case: :lower
             )

    assert value.data["producer"] == Artifacts.current()["producer"]
    assert Map.keys(value.data["schemas"]) |> Enum.sort() == ~w(bundle definition draft profile)
  end

  test "artifact substitution and native forgery refuse before schema execution" do
    artifacts = Artifacts.current()

    for altered <- [
          put_in(artifacts, ["producer", "sha256"], String.duplicate("a", 64)),
          put_in(artifacts, ["schemas", "profile", "title"], "substituted"),
          Map.put(artifacts, "semantic_rules", [])
        ] do
      assert {:error, %Error{code: :invalid_contract}} =
               Contract.export([], [], F.json("authoring-limits"), altered)
    end

    assert {:ok, value} = contract()

    assert {:error, %Error{code: :invalid_contract}} =
             Contract.new(%{value | sha256: String.duplicate("a", 64)})

    assert {:error, %Error{}} = Contract.new(Map.put(value, :extra, "secret"))
    assert {:error, %Error{}} = Contract.new(value.data)
    assert {:error, %Error{}} = Contract.parse(~s({"format":1,"format":2}))
    assert {:error, %Error{}} = Contract.parse("{}")
    assert {:error, %Error{}} = Contract.parse(1)
  end

  test "every authoring limit is required, bounded and revalidated" do
    limits = F.json("authoring-limits")
    assert {:ok, checked} = AuthoringLimits.new(limits)
    assert {:ok, ^limits} = AuthoringLimits.to_map(checked)

    for key <- ~w(max_bundle_bytes max_diagnostics max_report_bytes max_check_steps) do
      for value <- [0, nil, limits[key] + 1] do
        assert {:error, %Error{}} = AuthoringLimits.new(Map.put(limits, key, value))
      end

      assert {:error, %Error{}} = AuthoringLimits.new(Map.delete(limits, key))
    end

    assert {:error, %Error{}} = AuthoringLimits.new(Map.put(checked, :extra, 1))
    assert {:error, %Error{}} = Contract.export([%{}], [], limits, Artifacts.current())

    assert {:error, %Error{code: :input_limit}} =
             Contract.export(
               List.duplicate(F.json("installed-binding"), 65),
               [],
               limits,
               Artifacts.current()
             )

    assert {:error, %Error{}} =
             Contract.export([F.json("installed-binding") | :bad], [], limits, Artifacts.current())

    assert {:error, %Error{}} =
             Contract.export([], [], Map.put(limits, "reader", %{}), Artifacts.current())
  end

  test "large envelopes, malformed native values and lossy decimal source refuse" do
    assert {:ok, value} = contract()
    assert {:ok, bytes} = Contract.encode(value)
    assert {:error, %Error{code: :input_limit}} = Contract.parse(String.duplicate("x", 2_097_153))
    assert {:error, %Error{code: :numeric_limit}} = Contract.parse("1.10000000000000001")

    assert {:error, %Error{code: :numeric_limit}} =
             Contract.new(%{value | data: Map.put(value.data, "foreign", Integer.pow(10, 128))})

    assert {:error, %Error{}} = Contract.new(%{value | data: Map.put(value.data, :foreign, 1)})

    assert {:error, %Error{}} =
             Contract.parse(String.replace(bytes, "wotex.profile.authoring-contract@1", "wrong"))

    assert {:ok, binding} = Wotex.Profiles.Binding.new(F.json("installed-binding"), F.limits())

    assert {:ok, ^value} =
             Contract.export(
               [binding],
               F.json("installed-contracts"),
               F.json("authoring-limits"),
               Artifacts.current()
             )

    assert {:error, %Error{}} = Contract.parse(~s({"secret":"\\u0000"}))
  end
end
