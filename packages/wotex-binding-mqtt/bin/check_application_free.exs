defmodule Wotex.Binding.MQTT.Check.ApplicationFree do
  @moduledoc false

  @spec main() :: :ok
  def main do
    unless Application.spec(:wotex_binding_mqtt, :mod) in [nil, [], :undefined] do
      System.halt(1)
    end

    :ok
  end
end

Wotex.Binding.MQTT.Check.ApplicationFree.main()
