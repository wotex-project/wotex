defmodule Wotex.Binding.MQTT.QoS do
  @moduledoc """
  Normalizes MQTT Quality of Service values at Form and client boundaries.

  `normalize/1` accepts integer levels `0`, `1`, and `2`, together with the
  equivalent string forms used by the dated WoT MQTT vocabulary. The result is
  the closed `t:t/0` type consumed by `Wotex.Binding.MQTT.Command` and
  `Wotex.Binding.MQTT.Delivery`. Every other value returns a structured
  `Wotex.Binding.MQTT.Error`.

  Normalization changes representation only. It does not negotiate a broker
  session, guarantee delivery, infer a subscription level, or authorize a
  publish. The client implementation remains responsible for applying the
  accepted level to its MQTT operation and reporting the level associated with
  each received Application Message.

  ## Examples

      iex> Wotex.Binding.MQTT.QoS.normalize("1")
      {:ok, 1}

      iex> Wotex.Binding.MQTT.QoS.normalize(2)
      {:ok, 2}
  """

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
       :protocol,
       "mqv:qos must be an integer or string from zero through two"
     )}
  end
end
