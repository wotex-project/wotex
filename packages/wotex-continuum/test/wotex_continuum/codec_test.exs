defmodule WotexContinuum.CodecTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias WotexContinuum.{CanonicalJSON, Codec, Error, Limits, Mode}

  test "native constructors and encoders reject invalid UTF-8 keys at safe parent paths" do
    for bytes <- [<<255>>, <<0xC0, 0xAF>>, <<0xED, 0xA0, 0x80>>, <<0xF0, 0x90>>] do
      extensions = %{"urn:example:payload" => [%{bytes => true}]}
      input = %{deployment: :saas, connectivity: :connected, extensions: extensions}
      path = "/extensions/urn:example:payload/0"
      assert {:error, %Error{code: :invalid_utf8, path: ^path}} = Mode.new(input)

      {:ok, valid} = Mode.new(Map.delete(input, :extensions))
      forged = %{valid | extensions: extensions}
      assert {:error, %Error{code: :invalid_utf8, path: ^path}} = Codec.encode(forged)
      assert {:error, %Error{code: :invalid_utf8, path: ^path}} = Codec.canonicalize(forged)

      assert {:error, %Error{code: :invalid_utf8, path: "/"}} =
               Mode.new(Map.put(input, bytes, true))

      assert {:error, %Error{code: :invalid_utf8, path: "/details/nested"}} =
               WotexContinuum.Failure.new(%{
                 code: "rejected",
                 message: "invalid input",
                 details: %{"nested" => %{bytes => nil}}
               })
    end
  end

  test "valid Unicode and empty JSON keys survive constructor and canonical round trips" do
    extensions = %{"urn:example:payload" => %{"温度" => %{"" => "é", "𝄞" => "å"}}}

    assert {:ok, mode} =
             Mode.new(%{deployment: :saas, connectivity: :connected, extensions: extensions})

    assert {:ok, encoded} = Codec.canonicalize(mode)
    assert {:ok, ^mode} = Codec.decode(encoded)
    assert {:ok, ^encoded} = Codec.canonicalize(mode)
  end

  test "registry errors are typed and never create dynamic modules" do
    assert {:error, %Error{code: :required}} = WotexContinuum.from_map(%{})
    assert {:error, %Error{code: :unknown_kind}} = WotexContinuum.from_map(%{"kind" => "unknown"})
    assert {:error, %Error{code: :invalid_type}} = WotexContinuum.from_map(%{"kind" => 1})

    assert {:error, %Error{code: :duplicate_field}} =
             WotexContinuum.from_map(%{:kind => "mode", "kind" => "mode"})

    assert {:error, %Error{code: :invalid_type}} = WotexContinuum.from_map([])
    assert {:error, %Error{code: :invalid_type}} = WotexContinuum.module_for_kind(1)
    assert {:error, %Error{code: :unsupported_value}} = WotexContinuum.to_map(%URI{})
  end

  test "rejects duplicate members before value construction" do
    source =
      ~s({"kind":"mode","kind":"mode","schema_version":"1.0.0","deployment":"saas","connectivity":"connected","extensions":{}})

    assert {:error, %Error{code: :duplicate_field, phase: :decode, path: "/kind"}} =
             Codec.decode(source)
  end

  test "rejects malformed JSON and non-object roots" do
    assert {:error, %Error{code: :invalid_json}} = Codec.decode(~s({"kind":))
    assert {:error, %Error{code: :invalid_type}} = Codec.decode(~s(["mode"]))
    assert {:error, %Error{code: :invalid_type}} = Codec.decode(%{})
  end

  test "enforces source, nesting, collection, and string limits" do
    source =
      ~s({"kind":"mode","schema_version":"1.0.0","deployment":"saas","connectivity":"connected","extensions":{}})

    assert {:error, %Error{code: :limit_exceeded}} = Codec.decode(source, max_bytes: 8)

    assert {:error, %Error{code: :limit_exceeded}} =
             Codec.decode(source, max_collection_size: 2)

    assert {:error, %Error{code: :limit_exceeded}} = Codec.decode(source, max_string_bytes: 4)

    deep = ~s({"a":{"b":{"c":true}}})
    assert {:error, %Error{code: :limit_exceeded}} = Codec.decode(deep, max_depth: 2)
    assert {:error, %Error{code: :invalid_utf8}} = Codec.decode(<<255>>)
  end

  test "validates limit configuration" do
    assert {:ok, %Limits{max_depth: 4}} = Limits.new(max_depth: 4)
    assert {:ok, %Limits{}} = Limits.new(Limits.defaults())
    assert {:error, %Error{code: :invalid_limit}} = Limits.new(max_depth: 0)
    assert {:error, %Error{code: :unknown_field}} = Limits.new(unknown: 1)
    assert {:error, %Error{code: :invalid_options}} = Limits.new([:not_a_keyword])
    assert {:error, %Error{code: :invalid_options}} = Limits.new(max_depth: 2, max_depth: 3)
  end

  test "canonical encoder handles every JSON scalar and rejects invalid values" do
    assert {:ok, ~s({"a":[null,true,false,1,1.5,"x"],"z":0})} =
             CanonicalJSON.encode(%{"z" => 0, "a" => [nil, true, false, 1, 1.5, "x"]})

    assert {:error, %Error{code: :invalid_key}} = CanonicalJSON.encode(%{atom: true})
    assert {:error, %Error{code: :invalid_json_value}} = CanonicalJSON.encode(self())
    assert {:error, %Error{code: :invalid_utf8}} = CanonicalJSON.encode(<<255>>)
  end

  test "regular and canonical codecs accept only registered structs" do
    assert {:ok, mode} = Mode.new(%{deployment: :hybrid, connectivity: :intermittent})
    assert {:ok, regular} = Codec.encode(mode)
    assert Jason.decode!(regular)["kind"] == "mode"
    assert {:ok, _} = Codec.canonicalize(mode)
    assert {:error, %Error{code: :unsupported_value}} = Codec.encode(%URI{})
    assert {:error, %Error{code: :invalid_options}} = Codec.encode(mode, [:malformed])
    assert {:error, %Error{code: :unknown_field}} = Codec.encode(mode, unknown: true)
    assert {:error, %Error{code: :invalid_type}} = Codec.encode(mode, canonical: :yes)
    assert {:ok, ^mode} = Mode.new(mode)
    assert Mode.deployments() == [:saas, :hybrid, :connected_onprem, :air_gapped]
    assert Mode.connectivity_states() == [:connected, :intermittent, :disconnected]

    assert {:error, %Error{code: :wrong_kind}} =
             Mode.new(%{kind: "capability", deployment: :saas, connectivity: :connected})

    assert {:error, %Error{code: :invalid_version}} =
             Mode.new(%{schema_version: "bad", deployment: :saas, connectivity: :connected})
  end
end
