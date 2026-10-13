defmodule Wotex.Routines.BasisTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{Basis, Continuum, Error, Fact, Limits, Registry, Unit}

  setup_all do
    corpus =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()
      |> Path.join("vectors/wro-01.json")
      |> File.read!()
      |> JSON.decode!()

    {:ok, limits} = Limits.new(corpus["limits"])
    {:ok, registry} = Registry.new(corpus["registry"], limits)
    %{corpus: corpus, limits: limits, registry: registry}
  end

  test "five independent interaction shapes retain exact installed semantics", context do
    for data <- context.corpus["bases"] do
      assert {:ok, basis} = Basis.new(data, context.registry, context.limits)
      assert {:ok, ^data} = Basis.to_map(basis, context.registry, context.limits)
      assert {:ok, digest} = Basis.semantic_digest(basis, context.limits)
      assert digest == data["semantic_digest"]
      assert basis.data["effects"]["repeat"] == "never"
    end

    [_, _, fast, slow, media] = context.corpus["bases"]
    assert fast["evidence"]["completion"] == "reported_match"
    assert slow["timing"]["duration_ms"] == 120_000
    assert media["value"]["enum"] == ["play", "stop"]
    assert media["output"] == nil
    assert slow["evidence"]["report_contract"]["id"] == "qualified-report"
  end

  test "uninstalled semantics and altered caller-built structs cannot widen the basis", context do
    data = hd(context.corpus["bases"])
    unknown = put_in(data, ["security_contract", "version"], "future")
    {:ok, digest} = Basis.semantic_digest(unknown, context.limits)
    unknown = Map.put(unknown, "semantic_digest", digest)

    assert {:error, %Error{code: :unknown_required_contract}} =
             Basis.new(unknown, context.registry, context.limits)

    report = put_in(data, ["evidence", "report_contract", "id"], "uninstalled-report")
    {:ok, digest} = Basis.semantic_digest(report, context.limits)
    report = Map.put(report, "semantic_digest", digest)
    roots = Enum.reject(context.registry.data, &(&1["id"] == report["id"]))
    root = Map.take(report, ~w(id version semantic_digest)) |> Map.put("requires", [])

    assert {:error, %Error{code: :unknown_required_contract}} =
             Basis.new(report, [root | roots], context.limits)

    assert {:error, %Error{code: :semantic_digest_mismatch}} =
             Basis.new(
               put_in(data, ["evidence", "completion"], "local_queue"),
               context.registry,
               context.limits
             )

    assert {:error, %Error{code: :unknown_field}} =
             Basis.new(Map.put(data, "raw_command", "write"), context.registry, context.limits)

    forged = struct!(Basis, data: Map.delete(data, "effects"))

    assert {:error, %Error{code: :missing_field}} =
             Basis.new(forged, context.registry, context.limits)

    assert {:error, %Error{code: :invalid_struct}} =
             Basis.new(Map.put(forged, :extra, nil), context.registry, context.limits)
  end

  test "offline closure rejects cycles, duplicate identities and missing imports", context do
    [first, second | _] = context.corpus["registry"]
    ref1 = Map.drop(first, ["requires"])
    ref2 = Map.drop(second, ["requires"])

    assert {:error, %Error{code: :cyclic_contract}} =
             Registry.new(
               [%{first | "requires" => [ref2]}, %{second | "requires" => [ref1]}],
               context.limits
             )

    assert {:error, %Error{code: :duplicate_identity}} =
             Registry.new([first, first], context.limits)

    assert {:error, %Error{code: :unknown_required_contract}} =
             Registry.new([%{first | "requires" => [ref2]}], context.limits)

    assert {:error, %Error{code: :duplicate_identity}} =
             Registry.new([first, %{second | "requires" => [ref1, ref1]}], context.limits)
  end

  test "coupled affordances resolve to the same whole resource and require every role", context do
    fast = Enum.at(context.corpus["bases"], 2)
    slow = Enum.at(context.corpus["bases"], 3)

    for basis <- [fast, slow] do
      assert {:ok, ["station:1"]} =
               Basis.domains(basis, %{"target" => "station:1"}, context.registry, context.limits)

      assert {:error, %Error{code: :missing_field}} =
               Basis.domains(basis, %{}, context.registry, context.limits)

      assert {:error, %Error{code: :unknown_field}} =
               Basis.domains(
                 basis,
                 %{"target" => "station:1", "extra" => "station:2"},
                 context.registry,
                 context.limits
               )
    end
  end

  test "hand-calculated dimensional vectors use exact arithmetic", context do
    for vector <- context.corpus["conversions"] do
      {:ok, from} = Unit.new(vector["from"], context.limits)
      {:ok, to} = Unit.new(vector["to"], context.limits)
      result = Unit.convert(vector["input"], from, to, context.limits)

      if Map.has_key?(vector, "output") do
        assert result == {:ok, vector["output"]}
      else
        assert {:error, %Error{code: code}} = result
        assert Atom.to_string(code) == vector["error"]
      end
    end

    unit = hd(context.corpus["conversions"])["from"]

    assert {:error, %Error{code: :out_of_domain}} =
             Unit.new(%{unit | "scale_d" => 0}, context.limits)

    assert {:error, %Error{}} = Unit.convert(0.0, unit, unit, context.limits)
    assert {:error, %Error{}} = Unit.to_map(struct!(Unit, data: nil), context.limits)
  end

  test "exact conversion refuses overflow without iterating over the scale", context do
    maximum = context.corpus["limits"]["max_integer"]
    unit = hd(context.corpus["conversions"])["to"]
    source = %{unit | "scale_n" => maximum, "scale_d" => 1, "min" => 0, "max" => maximum}
    destination = %{unit | "scale_n" => 1, "scale_d" => 1, "min" => 0, "max" => maximum}

    assert {:error, %Error{code: :integer_overflow}} =
             Unit.convert(maximum, source, destination, context.limits)
  end

  test "unknown, replay, baseline and source epochs remain separate facts", context do
    fact = context.corpus["fact"]

    assert {:error, %Error{code: :missing_field}} =
             Fact.new(Map.delete(fact, "source_class"), context.limits)

    assert {:error, %Error{}} =
             Fact.new(%{fact | "source_class" => "derived_report"}, context.limits)

    for quality <- ~w(usable stale invalid unknown),
        replay <- ~w(fresh retained replayed),
        continuity <- ~w(continuous baseline lost) do
      data = %{fact | "quality" => quality, "replay" => replay, "continuity" => continuity}
      assert {:ok, value} = Fact.new(data, context.limits)
      assert {:ok, ^data} = Fact.to_map(value, context.limits)
    end

    unknown = %{
      fact
      | "value" => nil,
        "quality" => "unknown",
        "source_time" => nil,
        "source_time_trust" => "unknown",
        "source_time_basis" => nil,
        "source_uncertainty_ms" => nil
    }

    assert {:ok, %Fact{data: %{"value" => nil}}} = Fact.new(unknown, context.limits)

    assert {:error, %Error{code: :invalid_quality}} =
             Fact.new(%{unknown | "quality" => "usable"}, context.limits)

    assert {:ok, %Fact{data: %{"source_epoch" => "connection:2", "sequence" => 0}}} =
             Fact.new(%{fact | "source_epoch" => "connection:2", "sequence" => 0}, context.limits)
  end

  test "derived expiry cannot outrun a contributor or cross its receipt epoch", context do
    raw = context.corpus["fact"]

    contributor = %{
      "fact_id" => "sample:1",
      "source_id" => "sensor:2",
      "source_epoch" => "connection:2",
      "sequence" => 1,
      "receipt_epoch" => "boot:1",
      "expires_ms" => 1010
    }

    derived = %{
      raw
      | "source_class" => "derived_report",
        "derivation_digest" => raw["profile_digest"],
        "contributors" => [contributor]
    }

    assert {:ok, _} = Fact.new(derived, context.limits)

    assert {:error, %Error{code: :invalid_derivation_basis}} =
             Fact.new(
               %{derived | "contributors" => [%{contributor | "expires_ms" => 1000}]},
               context.limits
             )

    assert {:error, %Error{code: :invalid_derivation_basis}} =
             Fact.new(
               %{derived | "contributors" => [%{contributor | "receipt_epoch" => "boot:old"}]},
               context.limits
             )

    assert {:error, %Error{code: :duplicate_identity}} =
             Fact.new(%{derived | "contributors" => [contributor, contributor]}, context.limits)
  end

  test "invalid sentinels and source-clock uncertainty survive without gaining usability",
       context do
    raw = context.corpus["fact"]
    sentinel = raw["unit"]["max"] + 1

    assert {:ok, %Fact{data: %{"value" => ^sentinel, "quality" => "invalid"}}} =
             Fact.new(%{raw | "value" => sentinel, "quality" => "invalid"}, context.limits)

    assert {:error, %Error{code: :out_of_domain}} =
             Fact.new(%{raw | "value" => sentinel}, context.limits)

    for key <- ~w(source_time source_time_basis source_uncertainty_ms) do
      assert {:error, %Error{code: :missing_clock_basis}} =
               Fact.new(Map.put(raw, key, nil), context.limits)
    end

    assert {:ok, %Fact{data: %{"source_time_trust" => "untrusted"}}} =
             Fact.new(%{raw | "source_time_trust" => "untrusted"}, context.limits)
  end

  test "Continuum retains every required field and refuses missing source time", context do
    data = context.corpus["fact"]

    scope = %{
      "execution_id" => "execution:1",
      "node_id" => "node:1",
      "observed_at" => data["received_at"],
      "mode" => %{
        "deployment" => "air_gapped",
        "connectivity" => "disconnected",
        "extensions" => %{}
      },
      "extensions" => %{}
    }

    {:ok, fact} = Fact.new(data, context.limits)
    assert {:ok, observation} = Continuum.to_observation(fact, scope, [], context.limits)
    assert {:ok, wire} = WotexContinuum.to_map(observation)
    assert {:ok, %Fact{data: ^data}} = Continuum.from_observation(wire, context.limits)

    for key <- ~w(sequence extensions) do
      assert {:error, %Error{}} = Continuum.from_observation(Map.delete(wire, key), context.limits)
    end

    assert {:error, %Error{code: :unsupported_quality}} =
             Continuum.from_observation(
               %{wire | "quality" => %{"routine_quality" => "usable", "extra" => true}},
               context.limits
             )

    assert {:error, %Error{code: :missing_source_time}} =
             Continuum.to_observation(
               %{
                 data
                 | "source_time" => nil,
                   "source_time_trust" => "unknown",
                   "source_time_basis" => nil,
                   "source_uncertainty_ms" => nil
               },
               scope,
               [],
               context.limits
             )
  end

  test "selected native bounds apply before semantic construction", context do
    data = hd(context.corpus["bases"])
    narrow = %{context.limits.data | "max_bytes" => 100}
    assert {:error, %Error{code: :limit_or_json_error}} = Basis.new(data, context.registry, narrow)
    assert {:error, %Error{code: :invalid_limits}} = Limits.new(Map.delete(narrow, "max_integer"))
    huge = :erlang.bsl(1, 1_000_000)

    assert {:error, %Error{code: :integer_overflow}} =
             Fact.new(%{context.corpus["fact"] | "value" => huge}, context.limits)

    for invalid <- [nil, false, 1, [], %{}, %{data: nil}, struct!(Fact, data: nil)] do
      assert {:error, %Error{}} = Fact.new(invalid, context.limits)
    end
  end
end
