defmodule Wotex.BACnet.ContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "package does not register an application callback" do
    assert Application.spec(:wotex_bacnet, :mod) in [nil, [], :undefined]
  end

  test "structured failures do not imply retries or effects" do
    error = Wotex.BACnet.Error.new(:invalid_value, :address)
    assert error.code == :invalid_value
    assert error.field == :address
    refute error.retryable
    assert error.effect == :none
  end
end
