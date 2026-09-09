defmodule Wotex.Binding.MQTT.QoSTest do
  @moduledoc false

  use ExUnit.Case, async: true
  doctest Wotex.Binding.MQTT.QoS

  alias Wotex.Binding.MQTT.{Error, QoS}

  test "normalizes integer and string QoS levels" do
    for level <- 0..2 do
      assert {:ok, ^level} = QoS.normalize(level)
      assert {:ok, ^level} = QoS.normalize(Integer.to_string(level))
    end
  end

  test "rejects values outside MQTT QoS levels" do
    for invalid <- [-1, 3, "3", :one, nil] do
      assert {:error, %Error{code: :invalid_qos}} = QoS.normalize(invalid)
    end
  end
end
