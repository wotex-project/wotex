defmodule Wotex.Binding.MQTT.QoS do
  @moduledoc "MQTT Quality of Service normalization."

  alias Wotex.Binding.MQTT.Error

  @type t :: 0 | 1 | 2

  @doc "Normalizes an integer or string QoS level from zero through two."
  @spec normalize(term()) :: {:ok, t()} | {:error, Error.t()}
  def normalize(value) when value in [0, 1, 2], do: {:ok, value}
  def normalize("0"), do: {:ok, 0}
  def normalize("1"), do: {:ok, 1}
  def normalize("2"), do: {:ok, 2}

  def normalize(_value) do
    {:error,
     Error.new(
       :invalid_qos,
       :command,
       "mqv:qos must be an integer or string from zero through two"
     )}
  end
end
