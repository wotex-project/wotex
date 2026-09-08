defmodule WotexContinuum.DependencySecurityTest do
  @moduledoc false

  use ExUnit.Case, async: true

  @decimal_lock {:hex, :decimal, "3.1.1",
                 "430d87b04011ce6cbd4fd205be758311a81f87d552d40904abd00f015935b1d0", [:mix], [],
                 "hexpm", "c5f25f2ced74a0587d03e6023f595db8e924c9d3922c8c8ffd9edfc4498cf1f6"}

  test "the advisory acknowledgement applies only to the reviewed Decimal cohort" do
    assert Mix.Dep.Lock.read()[:decimal] == @decimal_lock
    assert Application.spec(:decimal, :vsn) == ~c"3.1.1"
    assert Mix.Project.config()[:hex][:ignore_advisories] == ["EEF-CVE-2026-32686"]
  end

  test "default parser limits reject the reported payload and enforce exact thresholds" do
    task =
      Task.async(fn ->
        for input <- [
              "1e1000000000",
              "1e-1000000000",
              "1e6145",
              "1e-6145",
              String.duplicate("1", 35)
            ] do
          assert Decimal.parse(input) == :error
          assert Decimal.cast(input) == :error
          assert_raise Decimal.Error, fn -> Decimal.new(input) end
        end

        for input <- ["1e6144", "1e-6144", String.duplicate("1", 34)] do
          assert {%Decimal{}, ""} = Decimal.parse(input)
          assert {:ok, %Decimal{}} = Decimal.cast(input)
          assert %Decimal{} = Decimal.new(input)
        end

        :ok
      end)

    try do
      assert {:ok, :ok} = Task.yield(task, 1_000)
    after
      Task.shutdown(task, :brutal_kill)
    end
  end
end
