defmodule WotexContinuum.ValidationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias WotexContinuum.{Error, Failure, Validation}

  test "normalizes known atom and string fields without creating atoms" do
    assert {:ok, %{name: "example"}} = Validation.normalize(%{"name" => "example"}, [:name])
    assert {:ok, %{name: "example"}} = Validation.normalize(%{name: "example"}, [:name])

    assert {:error, %Error{code: :duplicate_field}} =
             Validation.normalize(%{:name => "a", "name" => "b"}, [:name])

    assert {:error, %Error{code: :unknown_field}} = Validation.normalize(%{"other" => 1}, [:name])
    assert {:error, %Error{code: :unknown_field}} = Validation.normalize(%{other: 1}, [:name])
    assert {:error, %Error{code: :invalid_key}} = Validation.normalize(%{1 => "bad"}, [:name])
    assert {:error, %Error{code: :invalid_type}} = Validation.normalize([], [:name])
    assert {:error, %Error{code: :invalid_type}} = Validation.normalize(%URI{}, [:name])
  end

  test "validates strings, identifiers, IRIs, digests, and semantic versions" do
    assert {:ok, "example"} = Validation.string("example", ["value"])
    assert {:ok, nil} = Validation.optional_string(nil, ["value"], [])
    assert {:error, %Error{code: :too_short}} = Validation.string("", ["value"])
    assert {:error, %Error{code: :too_long}} = Validation.string("abcd", ["value"], max: 3)
    assert {:error, %Error{code: :invalid_utf8}} = Validation.string(<<255>>, ["value"])
    assert {:error, %Error{code: :invalid_type}} = Validation.string(1, ["value"])

    assert {:ok, "urn:example:thing:1"} = Validation.iri("urn:example:thing:1", ["iri"])
    assert {:error, %Error{code: :invalid_iri}} = Validation.iri("relative", ["iri"])

    digest = "sha256:" <> String.duplicate("a", 64)
    assert {:ok, ^digest} = Validation.digest(digest, ["digest"])
    assert {:error, %Error{code: :invalid_digest}} = Validation.digest("sha256:ABC", ["digest"])

    assert {:ok, "1.2.3"} = Validation.semver("1.2.3", ["version"])
    assert {:error, %Error{code: :invalid_version}} = Validation.semver("one", ["version"])
    assert {:ok, "~> 1.2"} = Validation.version_requirement("~> 1.2", ["requirement"])

    assert {:error, %Error{code: :invalid_version_requirement}} =
             Validation.version_requirement("not a range", ["requirement"])
  end

  test "normalizes timestamps and validates enums, booleans, and integers" do
    assert {:ok, "2026-09-02T08:00:00Z"} =
             Validation.timestamp("2026-09-02T10:00:00+02:00", ["at"])

    datetime = ~U[2026-09-02 10:00:00Z]
    assert {:ok, "2026-09-02T10:00:00Z"} = Validation.timestamp(datetime, ["at"])
    assert {:error, %Error{code: :invalid_timestamp}} = Validation.timestamp("today", ["at"])
    assert {:error, %Error{code: :invalid_type}} = Validation.timestamp(0, ["at"])

    assert {:ok, :ready} = Validation.enum(:ready, ["state"], [:ready])
    assert {:ok, :ready} = Validation.enum("ready", ["state"], [:ready])
    assert {:error, %Error{code: :invalid_enum}} = Validation.enum(:other, ["state"], [:ready])
    assert {:error, %Error{code: :invalid_enum}} = Validation.enum("other", ["state"], [:ready])
    assert {:error, %Error{code: :invalid_type}} = Validation.enum(1, ["state"], [:ready])

    assert {:ok, true} = Validation.boolean(true, ["flag"])
    assert {:error, %Error{code: :invalid_type}} = Validation.boolean(1, ["flag"])
    assert {:ok, 0} = Validation.non_negative_integer(0, ["count"])
    assert {:error, %Error{code: :invalid_integer}} = Validation.non_negative_integer(-1, ["count"])
    assert {:ok, 1} = Validation.positive_integer(1, ["count"])
    assert {:error, %Error{code: :invalid_integer}} = Validation.positive_integer(0, ["count"])
  end

  test "validates recursive JSON and extension maps" do
    value = %{"a" => [nil, true, 1, 1.5, "x", %{"b" => false}]}
    assert {:ok, ^value} = Validation.json_value(value, [])

    assert {:error, %Error{code: :invalid_key}} = Validation.json_value(%{atom: 1}, [])
    assert {:error, %Error{code: :invalid_json_value}} = Validation.json_value(self(), [])
    assert {:error, %Error{code: :invalid_json_value}} = Validation.json_value(%URI{}, [])

    deep = Enum.reduce(1..66, nil, fn _index, acc -> [acc] end)
    assert {:error, %Error{code: :limit_exceeded}} = Validation.json_value(deep, [])

    extensions = %{"https://example.org/flag" => true}
    assert {:ok, ^extensions} = Validation.extensions(extensions, ["extensions"])
    assert {:error, %Error{code: :invalid_iri}} = Validation.extensions(%{"flag" => true}, [])
    assert {:error, %Error{code: :invalid_type}} = Validation.extensions([], [])
  end

  test "validates collections and nested values with exact paths" do
    assert {:ok, ["a", "b"]} = Validation.string_list(["a", "b"], ["items"])

    assert {:error, %Error{code: :duplicate_value}} =
             Validation.string_list(["a", "a"], ["items"])

    assert {:error, %Error{code: :too_short}} =
             Validation.string_list([], ["items"], list_min: 1)

    assert {:ok, [:a, :b]} = Validation.enum_list(["a", :b], ["items"], [:a, :b], min: 1)
    assert {:error, %Error{code: :invalid_type}} = Validation.list(%{}, ["items"])
    assert :ok = Validation.uniqueness([1, 2], ["items"])

    assert {:ok, failure} = Failure.new(%{code: "failed", message: "example"})
    assert {:ok, [^failure]} = Validation.structs([failure], ["failures"], Failure)
    assert {:ok, ^failure} = Validation.nested(failure, ["failure"], Failure)

    assert {:error, %Error{path: ["failures", 0, "code"]}} =
             Validation.structs([%{message: "missing code"}], ["failures"], Failure)

    assert {:ok, [2, 4]} =
             Validation.map_list([1, 2], [], fn value, _path -> {:ok, value * 2} end)
  end

  test "converts nested values to wire terms and compares timestamps" do
    assert {:ok, failure} = Failure.new(%{code: "failed", message: "example"})

    assert %{"failure" => %{"code" => "failed"}} =
             Validation.to_wire(%{failure: failure})
             |> update_in(["failure"], &Map.drop(&1, ["details", "message"]))

    assert ["ready", %{"state" => "staged"}] =
             Validation.to_wire([:ready, %{state: :staged}])

    assert Validation.compare_timestamps("2026-09-02T10:00:00Z", "2026-09-02T10:00:01Z") == :lt
  end

  test "typed errors render deterministic paths" do
    error = %Error{code: :invalid, message: "bad value", path: ["items", 2, "id"]}
    assert Exception.message(error) == "$.items[2].id: bad value"
    assert Exception.message(%{error | path: []}) == "bad value"
    assert Error.prepend(error, "root").path == ["root", "items", 2, "id"]
  end
end
