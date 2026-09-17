defmodule Wotex.OPCUA.Native.SourceTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.OPCUA.Native.Source
  doctest Source

  @manifest Path.expand("../../../../priv/fixtures/native-sources-v1.json", __DIR__)

  test "WOP-X01 WOP-X02 source selectors bind exact reviewed runtime archive identities" do
    bytes = File.read!(@manifest)
    manifest = Jason.decode!(bytes)
    assert Source.manifest_digest() == Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

    for {name, root} <- [open62541: "open62541-1.5.7", openssl: "openssl-openssl-3.5.8"] do
      {:ok, source} = Source.fetch(name)
      recorded = Enum.find(manifest["sources"], &(&1["name"] == Atom.to_string(name)))
      assert source.root == root

      assert Map.drop(source, [:root]) ==
               Map.new(recorded, fn {k, v} -> {String.to_existing_atom(k), v} end)

      assert Regex.match?(~r/\A[0-9a-f]{64}\z/, source.sha256)
      assert Regex.match?(~r/\A[0-9a-f]{40}\z/, source.commit)
    end

    for value <- [nil, "openssl", :system, :asyncua, %{}, []] do
      assert Source.fetch(value) == {:error, :unsupported_native_source}
    end
  end

  test "WOP-X01 reviewed SDK patch script binds every original and modified file digest" do
    [patch] = Jason.decode!(File.read!(@manifest))["sdk_patches"]
    script = File.read!(Application.app_dir(:wotex_opcua, "priv/native/" <> patch["path"]))
    assert patch["sha256"] == Base.encode16(:crypto.hash(:sha256, script), case: :lower)
    assert patch["modified_source_license"] == "MPL-2.0"

    for file <- patch["files"] do
      assert script =~ file["path"]
      assert script =~ file["before_sha256"]
      assert script =~ file["after_sha256"]
    end
  end
end
