defmodule Wotex.Profiles.UnitConversionTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Profiles.{Error, Unit}
  alias Wotex.Profiles.Test.Fixtures, as: F

  test "independent exact Fraction vectors freeze representation and refusal" do
    for vector <- F.json("unit-conversion")["cases"] do
      limits = Map.put(F.limits(), "max_numeric_digits", vector["max_numeric_digits"])
      actual = Unit.convert(vector["value"], vector["source"], vector["target"], limits)

      case vector["expected"] do
        %{"error" => code} ->
          assert {:error, %Error{} = error} = actual, vector["name"]
          assert Atom.to_string(error.code) == code, vector["name"]

        expected ->
          assert actual == {:ok, expected}, vector["name"]
      end
    end
  end

  test "exact round trips retain decimal equality without ambient Decimal precision" do
    source = Map.merge(F.unit(), %{"scale_n" => "1", "scale_d" => "100"})
    target = F.unit()
    value = %{"type" => "sint", "value" => "5123"}
    before = Decimal.Context.get()
    Decimal.Context.set(%{before | precision: 1})

    try do
      assert {:ok, converted} = Unit.convert(value, source, target, F.limits())
      assert converted == %{"type" => "decimal", "coefficient" => "5123", "exponent" => -2}
      assert {:ok, ^value} = Unit.convert(converted, target, source, F.limits())
    after
      Decimal.Context.set(before)
    end
  end

  test "malformed arguments and selected aggregate budgets refuse" do
    unit = F.unit()
    value = %{"type" => "sint", "value" => "1"}

    for bad <- [
          1.0,
          nil,
          %{"type" => "sint", "value" => "01"},
          %{"type" => "decimal", "coefficient" => "10", "exponent" => 0}
        ] do
      assert {:error, %Error{}} = Unit.convert(bad, unit, unit, F.limits())
    end

    for {source, target, limits} <- [
          {%{}, unit, F.limits()},
          {unit, %{}, F.limits()},
          {unit, unit, %{}},
          {unit, unit, Map.put(F.limits(), "max_nodes", 1)}
        ] do
      assert {:error, %Error{}} = Unit.convert(value, source, target, limits)
    end

    # Each coordinate map fits this budget; the complete call envelope does not.
    budget = byte_size(F.encode(unit)) + 10
    limits = Map.put(F.limits(), "max_bytes", budget)
    assert {:ok, _} = Unit.new(unit, limits)
    assert {:error, %Error{code: :input_limit}} = Unit.convert(value, unit, unit, limits)
  end

  test "signed sums, cross products and representation powers respect the same bound" do
    unit = F.unit()
    limits = Map.put(F.limits(), "max_numeric_digits", 1)

    for {value, source} <- [
          {%{"type" => "sint", "value" => "-1"}, Map.put(unit, "offset_n", "-9")},
          {%{"type" => "sint", "value" => "-9"}, Map.put(unit, "scale_n", "2")},
          {%{"type" => "sint", "value" => "1"},
           Map.merge(unit, %{"scale_d" => "3", "offset_n" => "1", "offset_d" => "7"})},
          {%{"type" => "decimal", "coefficient" => "1", "exponent" => -1}, unit},
          {%{"type" => "sint", "value" => "1"}, Map.put(unit, "scale_n", "10")}
        ] do
      assert {:error, %Error{code: :numeric_limit}} = Unit.convert(value, source, unit, limits)
    end

    assert {:ok, %{"type" => "sint", "value" => "100"}} =
             Unit.convert(
               %{"type" => "decimal", "coefficient" => "1", "exponent" => 2},
               unit,
               unit,
               F.limits()
             )

    assert {:ok, %{"type" => "sint", "value" => "0"}} =
             Unit.convert(
               %{"type" => "decimal", "coefficient" => "0", "exponent" => 0},
               unit,
               unit,
               F.limits()
             )
  end
end
