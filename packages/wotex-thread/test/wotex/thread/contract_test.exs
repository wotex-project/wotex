defmodule Wotex.Thread.ContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "WTH-I01 package does not register an application callback" do
    assert Application.spec(:wotex_thread, :mod) in [nil, [], :undefined]
  end

  test "structured failures do not imply retries or effects" do
    error = Wotex.Thread.Error.new(:invalid_value, :address)
    assert error.code == :invalid_value
    assert error.field == :address
    assert error.class == :permanent
    refute error.retryable
    assert error.effect == :none
  end
end
