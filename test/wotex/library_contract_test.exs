defmodule Wotex.LibraryContractTest do
  @moduledoc false

  use ExUnit.Case, async: false

  doctest Wotex

  test "the library has no application callback" do
    assert Application.spec(:wotex, :mod) in [nil, [], :undefined]
  end

  test "the public media types and context are exact" do
    assert Wotex.td_media_type() == "application/td+json"
    assert Wotex.tm_media_type() == "application/tm+json"
    assert Wotex.td_context_1_1() == "https://www.w3.org/2022/wot/td/v1.1"
  end

  test "bundled schema bytes match the recorded digests" do
    td_schema =
      File.read!(Application.app_dir(:wotex, "priv/w3c/td-json-schema-validation-1.1.json"))

    tm_schema =
      File.read!(Application.app_dir(:wotex, "priv/w3c/tm-json-schema-validation-1.1.json"))

    assert sha256(td_schema) == Wotex.ThingDescription.schema_info().sha256
    assert sha256(tm_schema) == Wotex.ThingModel.schema_info().bundled_sha256
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
