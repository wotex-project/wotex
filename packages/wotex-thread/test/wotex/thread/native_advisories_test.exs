defmodule Wotex.Thread.NativeAdvisoriesTest do
  @moduledoc false

  use ExUnit.Case, async: true

  @dependencies "priv/openthread/dependencies.json"
  @advisories "priv/provenance/native-advisories.json"

  test "native advisory sources are the exact build pins" do
    pins = Jason.decode!(File.read!(@dependencies))
    review = Jason.decode!(File.read!(@advisories))

    assert Map.keys(review) |> Enum.sort() == ~w(format reviewed reviews sources version)
    assert review["format"] == "wotex.native-advisories" and review["version"] == 1

    sources = Map.new(review["sources"], &{&1["component"], &1})
    assert Map.keys(sources) |> Enum.sort() == ~w(json mbedtls mbedtls-framework openthread)

    for name <- ~w(openthread mbedtls mbedtls-framework) do
      assert Map.take(sources[name], ~w(repository commit)) ==
               Map.take(pins["sources"][name], ~w(repository commit))
    end

    assert sources["json"]["tag"] == "v" <> pins["json"]["version"]
    assert Enum.all?(Map.values(sources), &(&1["commit"] =~ ~r/\A[0-9a-f]{40}\z/))

    queries = Enum.flat_map(Map.values(sources), & &1["nvd"])

    assert Enum.all?(
             queries,
             &match?(
               [{kind, value}] when kind in ["cpe", "keyword"] and is_binary(value),
               Map.to_list(&1)
             )
           )
  end

  test "every native advisory review is complete, unique and not a waiver" do
    review = Jason.decode!(File.read!(@advisories))
    components = Enum.map(review["sources"], & &1["component"])
    keys = Enum.map(review["reviews"], &{&1["component"], &1["id"]})
    assert keys == Enum.uniq(keys)

    for entry <- review["reviews"] do
      assert entry["id"] =~ ~r/\A(CVE-\d{4}-\d{4,}|GHSA(-[23456789cfghjmpqrvwx]{4}){3})\z/
      assert entry["component"] in components
      assert is_binary(entry["reason"]) and byte_size(entry["reason"]) > 0

      case entry["decision"] do
        "fixed_in_pin" ->
          assert [_ | _] = entry["fix_commits"]
          assert Enum.all?(entry["fix_commits"], &(&1 =~ ~r/\A[0-9a-f]{40}\z/))
          assert Map.keys(entry) |> Enum.sort() == ~w(component decision fix_commits id reason)

        decision when decision in ["not_applicable", "unrelated"] ->
          assert Map.keys(entry) |> Enum.sort() == ~w(component decision id reason)
      end
    end
  end
end
