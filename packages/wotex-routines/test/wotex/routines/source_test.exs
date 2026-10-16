defmodule Wotex.Routines.SourceTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{Codec, Error, Limits, Profile, Source}

  @profile %{
    "source_bytes" => 65_536,
    "source_depth" => 32,
    "expanded_nodes" => 64,
    "predicate_nodes" => 64,
    "invocation_depth" => 4,
    "parallel_width" => 4,
    "effects" => 16,
    "waits" => 16,
    "active_definitions" => 64,
    "active_runs" => 64,
    "pending_work" => 64,
    "run_ms" => 86_400_000
  }
  @literal %{"op" => "literal", "value" => true}
  @effect %{
    "id" => "apply",
    "kind" => "effect",
    "binding" => "actuator",
    "input" => %{"parameter" => "enabled"},
    "completion" => "reported_match"
  }
  @source %{
    "format" => "wotex.routines.source@1",
    "profile" => "bounded-composition@1",
    "id" => "procedure:1",
    "revision" => "1",
    "parameters" => %{"enabled" => %{"type" => "boolean", "unit" => nil, "enum" => []}},
    "bindings" => ["actuator", "sensor"],
    "trigger" => %{"kind" => "manual"},
    "condition" => @literal,
    "steps" => @effect,
    "overlap" => "reject",
    "run_ms" => 60_000
  }

  setup_all do
    {:ok, profile} = Profile.new(@profile)

    {:ok, limits} =
      Limits.new(%{
        "max_bytes" => 65_536,
        "max_depth" => 32,
        "max_nodes" => 4096,
        "max_string_bytes" => 4096,
        "max_collection_size" => 256,
        "max_integer" => 9_223_372_036_854_775_807
      })

    priv =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()

    schema =
      priv
      |> Path.join("schemas/wro-02-source.schema.json")
      |> File.read!()
      |> JSON.decode!()

    %{profile: profile, limits: limits, schema: ExJsonSchema.Schema.resolve(schema)}
  end

  test "explicit limit ceilings and forged native limit maps cannot widen source admission", c do
    assert Limits.to_map(c.limits) == {:ok, c.limits.data}

    for selected <- [
          %{c.limits.data | "max_bytes" => 0},
          %{c.limits.data | "max_depth" => 65},
          %{c.limits.data | "max_integer" => 9_223_372_036_854_775_808},
          Map.delete(c.limits.data, "max_nodes"),
          Map.put(c.limits.data, "extra", 1)
        ] do
      assert {:error, %Error{code: :invalid_limits}} = Limits.new(selected)
      assert {:error, %Error{}} = Codec.decode_source("{}", c.profile, selected)
    end
  end

  test "every declared structural step survives complete canonical round trip", context do
    nodes = [
      @effect,
      %{"kind" => "noop", "id" => "empty"},
      %{"kind" => "sequence", "id" => "series", "steps" => [@effect]},
      %{
        "kind" => "parallel",
        "id" => "fork",
        "branches" => [@effect, %{"kind" => "noop", "id" => "other"}]
      },
      %{
        "kind" => "if",
        "id" => "choice",
        "condition" => @literal,
        "then" => @effect,
        "else" => %{"kind" => "noop", "id" => "other"}
      },
      %{"kind" => "wait", "id" => "wait", "condition" => @literal, "timeout_ms" => 500},
      %{"kind" => "delay", "id" => "delay", "duration_ms" => 500},
      %{
        "kind" => "invoke",
        "id" => "call",
        "routine_id" => "procedure:2",
        "revision" => "2",
        "arguments" => %{"child" => %{"parameter" => "enabled"}}
      }
    ]

    for node <- nodes do
      data = %{@source | "steps" => node}
      assert :ok == ExJsonSchema.Validator.validate(context.schema, data)
      assert {:ok, source} = Source.new(data, context.profile, context.limits)
      assert {:ok, bytes} = Codec.encode_source(source, context.profile, context.limits)
      assert {:ok, ^source} = Codec.decode_source(bytes, context.profile, context.limits)
      assert {:ok, ^data} = Source.to_map(source, context.profile, context.limits)
    end
  end

  test "structural admission refuses unsupported syntax, duplicate steps and undeclared references",
       context do
    invalid = [
      Map.put(@source, "script", "invoke"),
      %{@source | "overlap" => "queue"},
      %{@source | "steps" => %{"kind" => "toggle", "id" => "apply"}},
      %{@source | "steps" => %{@effect | "input" => %{"parameter" => "missing"}}},
      %{@source | "steps" => %{@effect | "binding" => "missing"}},
      %{@source | "steps" => %{"kind" => "sequence", "id" => "series", "steps" => []}},
      %{
        @source
        | "steps" => %{"kind" => "parallel", "id" => "fork", "branches" => [@effect, @effect]}
      }
    ]

    for data <- invalid do
      assert {:error, %Error{}} = Source.new(data, context.profile, context.limits)
    end
  end

  test "all possible branches count before execution and narrowed bounds cannot expand", context do
    source = %{
      @source
      | "steps" => %{
          "kind" => "if",
          "id" => "choice",
          "condition" => @literal,
          "then" => @effect,
          "else" => %{@effect | "id" => "other"}
        }
    }

    assert {:error, %Error{code: :effect_bound}} =
             Source.new(source, %{@profile | "effects" => 1}, context.limits)

    assert {:error, %Error{code: :node_bound}} =
             Source.new(source, %{@profile | "expanded_nodes" => 1}, context.limits)

    source = %{@source | "steps" => %{"kind" => "delay", "id" => "delay", "duration_ms" => 60_001}}

    assert {:error, %Error{code: :duration_bound}} =
             Source.new(source, context.profile, context.limits)

    assert {:error, %Error{code: :limit_or_json_error}} =
             Source.new(@source, %{@profile | "source_bytes" => 100}, context.limits)
  end

  test "trigger and predicate shapes remain explicit and hysteresis has ordered thresholds",
       context do
    predicates = [
      %{"op" => "literal", "value" => "unknown"},
      %{"op" => "eq", "binding" => "sensor", "value" => false},
      %{"op" => "not", "arg" => @literal},
      %{"op" => "all", "args" => [@literal, %{"op" => "literal", "value" => false}]},
      %{"op" => "any", "args" => [@literal]}
    ]

    for predicate <- predicates do
      assert {:ok, _} =
               Source.new(%{@source | "condition" => predicate}, context.profile, context.limits)
    end

    edge = %{
      "kind" => "edge",
      "binding" => "sensor",
      "direction" => "rising",
      "debounce_ms" => 10,
      "cooldown_ms" => 50,
      "hysteresis" => %{"enter" => 20, "exit" => 10}
    }

    assert {:ok, _} = Source.new(%{@source | "trigger" => edge}, context.profile, context.limits)

    assert {:error, %Error{code: :invalid_hysteresis}} =
             Source.new(
               %{@source | "trigger" => put_in(edge, ["hysteresis", "exit"], 20)},
               context.profile,
               context.limits
             )

    assert {:ok, _} =
             Source.new(
               %{
                 @source
                 | "trigger" => %{
                     "kind" => "due",
                     "schedule_id" => "schedule:1",
                     "schedule_basis" => "sha256:" <> String.duplicate("6", 64)
                   }
               },
               context.profile,
               context.limits
             )

    assert {:error, %Error{}} =
             Source.new(
               %{@source | "condition" => %{"op" => "all", "args" => []}},
               context.profile,
               context.limits
             )
  end

  test "malformed wire/native source never acquires defaults or an executable path", context do
    for bytes <- [nil, <<255>>, ~s({"format":1,"format":2}), ~s({"script":"execute"})] do
      assert {:error, %Error{}} = Codec.decode_source(bytes, context.profile, context.limits)
    end

    for key <- Map.keys(@source) do
      assert {:error, %Error{code: :missing_field}} =
               Source.new(Map.delete(@source, key), context.profile, context.limits)
    end

    assert {:error, %Error{}} =
             Source.to_map(struct!(Source, data: nil), context.profile, context.limits)

    assert {:error, %Error{}} =
             Source.new(
               Map.put(struct!(Source, data: @source), :extra, nil),
               context.profile,
               context.limits
             )
  end
end
