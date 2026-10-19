defmodule Wotex.Lab.DependencySecurityTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "the locked Gun rejects injected headers before dispatch with default options" do
    for injection <- ["value\r\ninjected: true", "value\ninjected: true"] do
      error =
        assert_raise ErlangError, fn ->
          :gun.get(self(), "/", [{"x-test", injection}])
        end

      assert {:invalid_request_header, "x-test", _} = error.original
      refute_received {:"$gen_cast", _}
    end
  end

  test "the locked Decimal rejects the reported unbounded exponent payload" do
    task =
      Task.async(fn ->
        parsed = Decimal.parse("1e1000000000")

        constructed =
          try do
            {:ok, Decimal.new("1e1000000000")}
          rescue
            error in Decimal.Error -> {:error, error.__struct__}
          end

        {parsed, constructed}
      end)

    on_exit(fn ->
      if Process.alive?(task.pid), do: Task.shutdown(task, :brutal_kill)
    end)

    assert {:ok, {:error, {:error, Decimal.Error}}} = Task.yield(task, 1_000)
  end
end
