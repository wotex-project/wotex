defmodule Wotex.Matter.Bridge.ConnectionConfiguration do
  @moduledoc false

  alias Wotex.Matter.Bridge.{ClockProjection, ConsumerConfiguration}
  alias Wotex.Matter.Error

  @keys [
    :owner,
    :executable,
    :executable_sha256,
    :arguments,
    :clock,
    :minimum_rate,
    :policy,
    :routes,
    :timeout
  ]

  @doc false
  @spec build(term()) :: {:ok, map()} | {:error, Error.t()}
  def build(options) when is_list(options) do
    with true <- Keyword.keyword?(options) and length(options) == length(@keys),
         value = Map.new(options),
         true <- Enum.sort(Map.keys(value)) == Enum.sort(@keys),
         true <- is_pid(value.owner) and node(value.owner) == node(),
         true <- path?(value.executable),
         true <- is_binary(value.executable_sha256),
         true <- Regex.match?(~r/\A[0-9a-f]{64}\z/, value.executable_sha256),
         true <- arguments?(value.arguments),
         true <- is_integer(value.timeout) and value.timeout in 1..5000,
         {:ok, _} <- ClockProjection.new(<<0::128>>, 0, 0, 0, value.minimum_rate),
         {:ok, _} <-
           ConsumerConfiguration.build(
             generation: <<0::128>>,
             receiver: self(),
             clock: value.clock,
             policy: value.policy,
             routes: value.routes
           ) do
      {:ok, value}
    else
      _ -> invalid()
    end
  rescue
    _ -> invalid()
  end

  def build(_), do: invalid()

  defp path?(value),
    do:
      is_binary(value) and byte_size(value) in 1..4096 and String.valid?(value) and
        Path.type(value) == :absolute and not String.contains?(value, [<<0>>, "\n", "\r"])

  defp arguments?(values) when is_list(values) and length(values) <= 32 do
    Enum.all?(values, fn value ->
      is_binary(value) and byte_size(value) <= 4096 and String.valid?(value) and
        not String.contains?(value, <<0>>)
    end) and Enum.reduce(values, 0, &(byte_size(&1) + &2)) <= 65_536
  end

  defp arguments?(_), do: false
  defp invalid, do: {:error, Error.new(:invalid_options)}
end
