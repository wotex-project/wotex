defmodule WotexLabWorkbench.MetricsTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.Metrics

  setup do
    pid =
      start_supervised!({Metrics, capacity: 16, name: WotexLabWorkbench.MetricsTest.Ring})

    %{ring: pid}
  end

  test "the synchronous ring is bounded and session scopes do not cross", %{ring: ring} do
    assert {:error, :unavailable} = Metrics.query(ring, scope: "alpha")

    for index <- 1..20 do
      scope = if rem(index, 2) == 0, do: "alpha", else: "beta"
      :ok = Metrics.record(scope, :scenario, :inference, %{duration: index}, %{outcome: :ok})
    end

    assert {:ok, alpha} = Metrics.query(ring, scope: "alpha", limit: 16)
    assert Enum.all?(alpha.samples, &(&1.scope == "alpha"))
    assert alpha.loss.capacity == 16
    assert alpha.loss.overwritten == 4
    assert alpha.watermark == 20

    assert {:ok, beta} = Metrics.query(ring, scope: "beta", limit: 2)
    assert length(beta.samples) == 2
    assert beta.truncated
    assert Enum.all?(beta.samples, &(&1.scope == "beta"))
  end

  test "closed query options reject malformed work before touching ETS", %{ring: ring} do
    for opts <- [
          [unknown: 1],
          [limit: 0],
          [limit: 2_001],
          [window_ms: 86_400_001],
          [scope: String.duplicate("x", 65)],
          [component: :caller],
          [operation: :caller],
          [limit: 1, limit: 2],
          [:malformed]
        ] do
      assert {:error, %Error{code: :invalid_query}} = Metrics.query(ring, opts)
    end

    assert {:error, %Error{code: :invalid_query}} = Metrics.query(ring, %{})
  end
end
