defmodule WotexLabWorkbench.DependencySecurityTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "the exact reviewed Decimal cohort rejects the advisory payload with default limits" do
    assert Application.spec(:decimal, :vsn) == ~c"3.1.1"

    task =
      Task.async(fn ->
        assert Decimal.Context.get().precision == 34

        for source <- ["1e1000000000", "1e-1000000000"] do
          assert Decimal.parse(source) == :error
          assert_raise Decimal.Error, fn -> Decimal.new(source) end
        end

        assert {Decimal.new("1.25"), ""} == Decimal.parse("1.25")
      end)

    on_exit(fn -> if Process.alive?(task.pid), do: Process.exit(task.pid, :kill) end)
    assert {:ok, _} = Task.yield(task, 1_000)
  end
end
