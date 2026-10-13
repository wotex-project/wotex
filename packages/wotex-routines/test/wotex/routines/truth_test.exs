defmodule Wotex.Routines.TruthTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{Error, Limits, Profile, Truth}

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
  @all [true, false, "unknown", false, false, false, "unknown", false, "unknown"]
  @any [true, true, true, true, false, "unknown", true, "unknown", "unknown"]

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

    %{profile: profile, limits: limits}
  end

  test "every pair matches independent three-valued truth tables", context do
    pairs = for a <- [true, false, "unknown"], b <- [true, false, "unknown"], do: [a, b]

    for {pair, expected} <- Enum.zip(pairs, @all) do
      assert Truth.combine("all", pair, context.profile, context.limits) == {:ok, expected}
    end

    for {pair, expected} <- Enum.zip(pairs, @any) do
      assert Truth.combine("any", pair, context.profile, context.limits) == {:ok, expected}
    end

    assert Truth.negate(true) == {:ok, false}
    assert Truth.negate(false) == {:ok, true}
    assert Truth.negate("unknown") == {:ok, "unknown"}
  end

  test "invalid truths, empty predicates and excessive width cannot become false", context do
    for input <- [nil, :unknown, 0, [], %{}] do
      assert {:error, %Error{code: :invalid_truth}} = Truth.negate(input)
    end

    for inputs <- [[], [nil], [0], ["false"], %{}] do
      assert {:error, %Error{}} = Truth.combine("all", inputs, context.profile, context.limits)
    end

    assert {:error, %Error{code: :unsupported_value}} =
             Truth.combine("quorum", [true], context.profile, context.limits)

    narrow = %{context.profile.data | "predicate_nodes" => 1}

    assert {:error, %Error{code: :predicate_bound}} =
             Truth.combine("all", [false, true], narrow, context.limits)
  end

  test "profile selections have no defaults and malformed structs refuse", context do
    assert Profile.to_map(context.profile) == {:ok, @profile}

    for data <- [
          Map.delete(@profile, "effects"),
          Map.put(@profile, "unknown", 1),
          %{@profile | "effects" => 0},
          %{@profile | "parallel_width" => 65}
        ] do
      assert {:error, %Error{code: :invalid_profile}} = Profile.new(data)
    end

    assert {:error, %Error{}} = Profile.new(Map.put(context.profile, :extra, nil))
    assert {:error, %Error{}} = Profile.to_map(struct!(Profile, data: nil))
  end
end
