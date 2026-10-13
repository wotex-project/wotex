defmodule Wotex.BLE.DependencySecurityTest do
  @moduledoc false

  use ExUnit.Case, async: true

  @decimal_lock {:hex, :decimal, "3.2.0",
                 "f1235f05d841a211fda78a08fdb9777f2ff51a71f18455233fae186ff76187c6", [:mix], [],
                 "hexpm", "190bca80580ce61aa69bb0eacadd7677710205c770225c2c2c07e32a5c31b234"}

  test "the Decimal parser regression stays pinned without advisory waivers" do
    assert Mix.Dep.Lock.read()[:decimal] == @decimal_lock
    assert Application.spec(:decimal, :vsn) == ~c"3.2.0"

    assert Mix.Project.config()
           |> Keyword.get(:hex, [])
           |> Keyword.get(:ignore_advisories, []) == []
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
