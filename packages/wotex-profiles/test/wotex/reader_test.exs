defmodule Wotex.Profiles.ReaderTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Profiles.{Definition, Definitions, Error, Limits, Profile, Unit}
  alias Wotex.Profiles.Test.Fixtures, as: F

  test "two independent fixture families match externally computed identities" do
    expected = F.json("identities")

    for family <- ~w(industrial research),
        {suffix, module} <-
          [{"profile", Profile}, {"definition", Definition}] do
      name = family <> "-" <> suffix
      assert {:ok, value} = module.parse(F.bytes(name), F.limits())
      assert value.raw_sha256 == expected[name]["raw_sha256"]
      assert value.semantic_sha256 == expected[name]["semantic_sha256"]
      assert {:ok, map} = module.to_map(value, F.limits())
      assert map == F.json(name)
      assert {:ok, reference} = module.reference(value, F.limits())
      assert reference == Map.put(Map.take(map, ~w(id version)), "sha256", value.semantic_sha256)
      assert {:ok, rebuilt} = module.new(value, F.limits())
      assert rebuilt.raw_sha256 == nil
      assert rebuilt.semantic_sha256 == value.semantic_sha256
    end
  end

  test "annotation and JSON key order do not change semantic identity" do
    for {module, original} <- [{Profile, F.profile()}, {Definition, F.definition()}] do
      assert {:ok, first} = module.new(original, F.limits())
      changed = Map.put(original, "annotations", %{"note" => "private", "empty" => ""})
      assert {:ok, second} = module.parse(F.encode(changed), F.limits())
      assert first.semantic_sha256 == second.semantic_sha256
      assert second.raw_sha256 != nil
    end
  end

  test "native values are revalidated, rehashed and cannot forge original byte custody" do
    for {module, original} <- [{Profile, F.profile()}, {Definition, F.definition()}] do
      assert {:ok, native} = module.parse(F.encode(original), F.limits())

      forged = %{
        native
        | raw_sha256: String.duplicate("b", 64),
          semantic_sha256: String.duplicate("c", 64)
      }

      assert {:ok, checked} = module.new(forged, F.limits())
      assert checked.raw_sha256 == nil
      assert checked.semantic_sha256 == native.semantic_sha256
      assert {:error, %Error{}} = module.new(Map.put(native, :extra, :private), F.limits())
      assert {:error, %Error{}} = module.new(%{native | raw_sha256: "bad"}, F.limits())
      assert {:error, %Error{}} = module.new(%{native | semantic_sha256: "bad"}, F.limits())
      assert {:error, %Error{}} = module.new(%{native | data: %{}}, F.limits())
    end

    assert {:error, %Error{}} =
             Profile.new(elem(Definition.new(F.definition(), F.limits()), 1), F.limits())

    assert {:error, %Error{}} = Profile.new(:unknown, F.limits())
  end

  test "complete limits refuse missing, extra, nonpositive and above-ceiling selections" do
    assert {:ok, limits} = Limits.new(F.limits())
    assert {:ok, limits} = Limits.new(limits)
    assert {:ok, map} = Limits.to_map(limits)
    assert map == F.limits()

    for {key, value} <- map do
      for bad <- [0, -1, value + 1, "1", nil] do
        assert {:error, %Error{code: :invalid_input, path: "/limits"}} =
                 Limits.new(Map.put(map, key, bad))
      end

      assert {:error, %Error{}} = Limits.new(Map.delete(map, key))
    end

    for bad <- [nil, Map.put(map, "extra", 1), Map.put(limits, :extra, 1), %{limits | data: :bad}] do
      assert {:error, %Error{}} = Limits.to_map(bad)
    end
  end

  test "byte, depth, node and coefficient budgets reject before reading a profile" do
    data = F.profile()
    bytes = F.encode(data)
    assert {:ok, _} = Profile.parse(bytes, Map.put(F.limits(), "max_bytes", byte_size(bytes)))

    assert {:error, %Error{code: :input_limit}} =
             Profile.parse(bytes, Map.put(F.limits(), "max_bytes", byte_size(bytes) - 1))

    for {key, value} <- [{"max_depth", 1}, {"max_nodes", 1}, {"max_bytes", 1}] do
      assert {:error, %Error{code: :input_limit}} =
               Profile.new(data, Map.put(F.limits(), key, value))

      assert {:error, %Error{code: :input_limit}} =
               Profile.parse(bytes, Map.put(F.limits(), key, value))
    end

    assert {:error, %Error{code: :numeric_limit}} =
             Profile.new(
               put_in(data, ["channels", Access.at(0), "selector", "register"], 123),
               Map.put(F.limits(), "max_numeric_digits", 2)
             )

    assert {:error, %Error{}} = Profile.new(Map.put(data, "requires", [1 | :bad]), F.limits())
    deep = Enum.reduce(1..20, 0, fn _, value -> [value] end)

    assert {:error, %Error{code: :input_limit}} =
             Profile.new(Map.put(data, "annotations", deep), F.limits())
  end

  test "source parser rejects duplicate names, malformed bytes and oversized numeric tokens" do
    for bytes <- ["{\"id\":1,\"id\":2}", "{\"secret\":1,\"secret\":2}", "[", <<255>>, "false"] do
      assert {:error, %Error{}} = Profile.parse(bytes, F.limits())
    end

    assert {:error, %Error{}} = Profile.parse(12, F.limits())
    assert {:error, %Error{}} = Profile.parse("{}", nil)

    for number <- [String.duplicate("1", 129), "1e1234567", "1E-1234567"] do
      assert {:error, %Error{code: :numeric_limit}} = Profile.parse(number, F.limits())
    end

    # Escaped quotes and huge digit strings are text, not numeric tokens.
    data =
      Map.put(F.profile(), "annotations", %{"note" => "quoted \"" <> String.duplicate("9", 200)})

    assert {:ok, _} = Profile.parse(F.encode(data), F.limits())
  end

  test "foreign keys, credentials and NUL never enter errors" do
    secret = "credential-canary-9029"

    for data <- [
          Map.put(F.profile(), secret, secret),
          put_in(F.profile(), ["channels", Access.at(0), "selector"], %{secret => <<0>>}),
          Map.put(F.profile(), "id", <<255>>),
          Map.put(F.profile(), "annotations", %{"note" => <<0>>}),
          Map.put(F.profile(), "annotations", %{:foreign => secret}),
          Map.put(F.profile(), :foreign, secret)
        ] do
      assert {:error, %Error{} = error} = Profile.new(data, F.limits())
      refute inspect(error) =~ secret
      assert error.path in ["", "/annotations"]
    end
  end

  test "closed identifiers, versions, formats and references have no guessing defaults" do
    for field <- ~w(format id version binding fingerprint channels requires) do
      assert {:error, %Error{}} = Profile.new(Map.delete(F.profile(), field), F.limits())
    end

    for value <- ["", "relative", "urn:" <> String.duplicate("x", 256), "bad id", 4] do
      assert {:error, %Error{}} = Profile.new(Map.put(F.profile(), "id", value), F.limits())
    end

    for value <- [
          "01.0.0",
          "1.2",
          "v1.2.3",
          "1.2.3-rc1",
          "65536.0.0",
          nil,
          String.duplicate("1", 30)
        ] do
      assert {:error, %Error{}} = Profile.new(Map.put(F.profile(), "version", value), F.limits())
    end

    assert {:error, %Error{code: :unsupported_format, path: "/format"}} =
             Profile.new(Map.put(F.profile(), "format", "future"), F.limits())

    for value <- [
          %{},
          %{"id" => "urn:valid", "version" => "1.0.0", "sha256" => String.duplicate("A", 64)},
          nil
        ] do
      assert {:error, %Error{}} = Profile.new(Map.put(F.profile(), "binding", value), F.limits())
    end
  end

  test "references and local channels are sorted and duplicate-free" do
    a = F.profile()["binding"]
    b = Map.put(a, "id", "urn:zzz")
    assert {:ok, _} = Profile.new(Map.put(F.profile(), "requires", [a, b]), F.limits())

    for refs <- [[b, a], [a, a], [a, Map.put(a, "sha256", String.duplicate("c", 64))]] do
      assert {:error, %Error{code: :reference_conflict}} =
               Profile.new(Map.put(F.profile(), "requires", refs), F.limits())
    end

    assert {:error, %Error{code: :input_limit}} =
             Profile.new(
               Map.put(F.profile(), "requires", [a, b]),
               Map.put(F.limits(), "max_dependencies", 1)
             )

    assert {:error, %Error{}} = Profile.new(Map.put(F.profile(), "requires", :bad), F.limits())
    [channel] = F.profile()["channels"]
    second = Map.put(channel, "id", "z")
    assert {:ok, _} = Profile.new(Map.put(F.profile(), "channels", [channel, second]), F.limits())

    assert {:error, %Error{code: :input_limit}} =
             Profile.new(
               Map.put(F.profile(), "channels", [channel, second]),
               Map.put(F.limits(), "max_channels", 1)
             )

    for channels <- [[channel, channel], [second, channel]] do
      assert {:error, %Error{code: :reference_conflict}} =
               Profile.new(Map.put(F.profile(), "channels", channels), F.limits())
    end

    for channels <- [[], nil, [Map.put(channel, "id", "bad key")]] do
      assert {:error, %Error{}} =
               Profile.new(Map.put(F.profile(), "channels", channels), F.limits())
    end
  end

  test "fingerprints are bounded literal predicates and channel operations match their kind" do
    [predicate] = F.profile()["fingerprint"]
    [channel] = F.profile()["channels"]

    for bad <- [
          nil,
          [],
          List.duplicate(predicate, 33),
          [Map.put(predicate, "field", "bad/key")],
          [Map.put(predicate, "operator", "regex")],
          [Map.put(predicate, "values", [])],
          [Map.put(predicate, "values", [hd(predicate["values"]), hd(predicate["values"])])],
          [
            Map.put(predicate, "values", [
              %{"type" => "decimal", "coefficient" => "1", "exponent" => 0}
            ])
          ]
        ] do
      assert {:error, %Error{}} = Profile.new(Map.put(F.profile(), "fingerprint", bad), F.limits())
    end

    values = [%{"type" => "text", "value" => "a"}, %{"type" => "text", "value" => "b"}]

    assert {:ok, _} =
             Profile.new(
               Map.put(F.profile(), "fingerprint", [
                 Map.merge(predicate, %{"operator" => "one_of", "values" => values})
               ]),
               F.limits()
             )

    assert {:error, %Error{}} =
             Profile.new(
               Map.put(F.profile(), "fingerprint", [Map.put(predicate, "values", values)]),
               F.limits()
             )

    for {kind, operations} <- [{"action", ["invokeaction"]}, {"event", ["subscribeevent"]}] do
      changed =
        Map.merge(channel, %{
          "affordance" => %{"kind" => kind, "name" => "sample"},
          "operations" => operations
        })

      assert {:ok, _} = Profile.new(Map.put(F.profile(), "channels", [changed]), F.limits())
    end

    for {key, bad} <- [
          {"operations", []},
          {"operations", nil},
          {"operations", ["invokeaction"]},
          {"operations", ["secret-op"]},
          {"operations", ["writeproperty", "readproperty"]},
          {"affordance", %{"kind" => "future", "name" => "x"}},
          {"affordance", %{"kind" => "property", "name" => ""}},
          {"selector", nil},
          {"required", 1},
          {"invalid_values", nil},
          {"invalid_values", List.duplicate(%{"type" => "null"}, 33)},
          {"invalid_values", [%{"type" => "list", "items" => []}]}
        ] do
      assert {:error, %Error{}} =
               Profile.new(
                 Map.put(F.profile(), "channels", [Map.put(channel, key, bad)]),
                 F.limits()
               )
    end
  end

  test "unit rationals are reduced, signed-64 and quantity meanings remain supplied" do
    assert {:ok, unit} = Unit.new(F.unit(), F.limits())
    assert {:ok, unit} = Unit.new(unit, F.limits())
    assert {:ok, map} = Unit.to_map(unit, F.limits())
    assert map == F.unit()

    for {key, value} <- [
          {"scale_n", "0"},
          {"scale_n", "-1"},
          {"scale_n", "01"},
          {"scale_d", "0"},
          {"offset_n", "-0"},
          {"offset_d", "2"},
          {"scale_n", "9223372036854775808"},
          {"scale_n", String.duplicate("1", 30)},
          {"quantity_kind", "relative"},
          {"dimension", [0]},
          {"dimension", [33, 0, 0, 0, 0, 0, 0]},
          {"dimension", [1.0, 0, 0, 0, 0, 0, 0]},
          {"scale_n", nil}
        ] do
      assert {:error, %Error{}} = Unit.to_map(Map.put(map, key, value), F.limits())
    end

    assert {:error, %Error{}} =
             Unit.new(Map.merge(map, %{"scale_n" => "2", "scale_d" => "4"}), F.limits())

    assert {:error, %Error{}} = Unit.new(Map.put(unit, :extra, 1), F.limits())
    assert {:ok, _} = Definition.new(Map.put(F.definition(), "unit", nil), F.limits())

    assert {:ok, _} =
             Definition.new(
               Map.put(F.definition(), "behaviour", F.profile()["binding"]),
               F.limits()
             )

    assert {:error, %Error{}} =
             Definition.new(Map.put(F.definition(), "behaviour", %{}), F.limits())
  end

  test "finite channel conversions cannot introduce executable templates or unordered tables" do
    affine = %{
      "kind" => "affine",
      "scale_n" => "1",
      "scale_d" => "2",
      "offset_n" => "-1",
      "offset_d" => "1"
    }

    a = %{
      "source" => %{"type" => "boolean", "value" => false},
      "target" => %{"type" => "sint", "value" => "0"}
    }

    b = %{
      "source" => %{"type" => "boolean", "value" => true},
      "target" => %{"type" => "sint", "value" => "1"}
    }

    for conversion <- [affine, %{"kind" => "table", "entries" => [a, b]}] do
      assert {:ok, _} =
               Profile.new(
                 put_in(F.profile(), ["channels", Access.at(0), "conversion"], conversion),
                 F.limits()
               )
    end

    for conversion <- [
          Map.put(affine, "expression", "run"),
          %{"kind" => "script"},
          %{"kind" => "table", "entries" => []},
          %{"kind" => "table", "entries" => [b, a]},
          %{"kind" => "table", "entries" => [a, a]},
          %{"kind" => "table", "entries" => [%{}]},
          %{
            "kind" => "table",
            "entries" => [Map.put(a, "source", %{"type" => "bytes", "base64" => "AB=="})]
          },
          %{
            "kind" => "table",
            "entries" => [Map.put(a, "target", %{"type" => "list", "items" => []})]
          }
        ] do
      assert {:error, %Error{}} =
               Profile.new(
                 put_in(F.profile(), ["channels", Access.at(0), "conversion"], conversion),
                 F.limits()
               )
    end
  end

  test "byte scalar literals remain inert sentinels and table operands" do
    bytes = %{"type" => "bytes", "base64" => "AA=="}
    data = put_in(F.profile(), ["channels", Access.at(0), "invalid_values"], [bytes])
    assert {:ok, _} = Profile.new(data, F.limits())

    for {source, target} <- [
          {bytes, %{"type" => "text", "value" => "literal"}},
          {%{"type" => "boolean", "value" => false}, bytes}
        ] do
      conversion = %{"kind" => "table", "entries" => [%{"source" => source, "target" => target}]}

      assert {:ok, _} =
               Profile.parse(
                 F.encode(put_in(data, ["channels", Access.at(0), "conversion"], conversion)),
                 F.limits()
               )
    end
  end

  test "definition sets are bounded, sorted and reject both identical and conflicting duplicates" do
    second = F.json("research-definition")
    assert {:ok, [a, b]} = Definitions.new([second, F.definition()], F.limits())
    assert a.data["id"] < b.data["id"]
    assert {:ok, []} = Definitions.new([], F.limits())

    assert {:error, %Error{code: :input_limit}} =
             Definitions.new([second, F.definition()], Map.put(F.limits(), "max_definitions", 1))

    assert {:error, %Error{code: :reference_conflict}} =
             Definitions.new([F.definition(), F.definition()], F.limits())

    assert {:error, %Error{}} = Definitions.new([%{}], F.limits())
    assert {:error, %Error{}} = Definitions.new(nil, F.limits())
  end

  test "malformed containers and stale native values remain total refusals" do
    assert {:ok, native} = Definition.new(F.definition(), F.limits())
    assert {:ok, [_]} = Definitions.new([native], F.limits())
    assert {:error, %Error{}} = Definitions.new([F.definition() | :bad], F.limits())
    assert {:ok, reconstructed} = Definition.new(native, F.limits())
    assert reconstructed.raw_sha256 == nil
    assert {:error, %Error{}} = Profile.new(Map.put(F.profile(), "requires", [%{}]), F.limits())
    [predicate] = F.profile()["fingerprint"]

    assert {:error, %Error{}} =
             Profile.new(
               Map.put(F.profile(), "fingerprint", [Map.put(predicate, "values", [%{}])]),
               F.limits()
             )

    assert {:error, %Error{}} =
             Profile.new(
               put_in(F.profile(), ["channels", Access.at(0), "invalid_values"], [%{}]),
               F.limits()
             )

    large = Integer.pow(10, 30)
    original = put_in(F.profile(), ["channels", Access.at(0), "selector", "register"], large)
    assert {:ok, value} = Profile.parse(F.encode(original), F.limits())
    assert value.data == original

    assert {:error, %Error{code: :numeric_limit}} =
             Profile.new(
               put_in(original, ["channels", Access.at(0), "selector", "register"], 1.0e19),
               F.limits()
             )

    for bytes <- ["--1", "1.", String.duplicate("-", 150), "0e999999"] do
      assert {:error, %Error{}} = Profile.parse(bytes, F.limits())
    end
  end

  test "annotation limits apply without affecting behavior" do
    for value <- [
          nil,
          [],
          %{"note" => 1},
          Map.new(1..17, &{Integer.to_string(&1), "x"}),
          %{"note" => String.duplicate("x", 1025)},
          Map.new(1..9, &{Integer.to_string(&1), String.duplicate("x", 1000)})
        ] do
      assert {:error, %Error{}} =
               Profile.new(Map.put(F.profile(), "annotations", value), F.limits())
    end
  end

  test "malformed native JSON is distinct from a selected resource limit" do
    for value <- [
          :foreign,
          {1, 2},
          <<255>>,
          %{non_string_key: 1},
          URI.new!("urn:example:value"),
          [1 | :foreign]
        ] do
      data = put_in(F.profile(), ["channels", Access.at(0), "selector"], value)
      assert {:error, %Error{code: :invalid_input}} = Profile.new(data, F.limits())
    end

    assert {:error, %Error{code: :input_limit}} =
             Profile.new(
               F.profile(),
               Map.put(F.limits(), "max_nodes", 1)
             )
  end
end
