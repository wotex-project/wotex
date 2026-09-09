defmodule Wotex.Thread.JoinerConfig do
  @moduledoc """
  Validates Thread joiner credentials and optional provisioning metadata.

  `new/1` requires a `:pskd` admitted by
  `Wotex.Thread.OpenThread.CommissioningValue`. An optional `:discerner` must
  be a `Wotex.Thread.JoinerIdentity` struct of the discerner variant.
  `:provisioning_url` and `:vendor_data` permit at most 64 UTF-8 bytes;
  `:vendor_name`, `:vendor_model` and `:vendor_sw_version` permit at most 32.
  Optional text may be absent or empty, but cannot contain ASCII control
  characters or DEL. The provisioning URL receives text validation only.
  Unknown fields and invalid values return `:invalid_joiner_config` errors.

  This module constructs inert values. It does not start a joiner or prove
  network admission, and joiner execution remains outside the implemented
  native profile. `Inspect` shows only the discerner; the struct and encoded
  parameters retain credentials and metadata under the caller's ownership.

  ## Examples

      iex> {:ok, config} = Wotex.Thread.JoinerConfig.new(%{pskd: "WTEST123"})
      iex> {config.discerner, config.vendor_name}
      {nil, nil}
  """

  alias Wotex.Thread.{Error, JoinerIdentity}
  alias Wotex.Thread.OpenThread.CommissioningValue

  @derive {Inspect, only: [:discerner]}
  @enforce_keys [:pskd]
  defstruct [
    :pskd,
    :discerner,
    :provisioning_url,
    :vendor_name,
    :vendor_model,
    :vendor_sw_version,
    :vendor_data
  ]

  @type t :: %__MODULE__{
          pskd: String.t(),
          discerner: nil | JoinerIdentity.t(),
          provisioning_url: nil | String.t(),
          vendor_name: nil | String.t(),
          vendor_model: nil | String.t(),
          vendor_sw_version: nil | String.t(),
          vendor_data: nil | String.t()
        }

  @fields %{
    provisioning_url: 64,
    vendor_name: 32,
    vendor_model: 32,
    vendor_sw_version: 32,
    vendor_data: 64
  }
  @keys [:pskd, :discerner | Map.keys(@fields)]

  @doc "Validates credentials and optional UTF-8 fields without consulting a device or environment."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%{pskd: pskd} = input) when map_size(input) <= 7 do
    with true <- Enum.all?(Map.keys(input), &(&1 in @keys)),
         true <- CommissioningValue.pskd?(pskd),
         true <-
           Enum.all?(@fields, fn {key, size} ->
             CommissioningValue.text?(Map.get(input, key), size)
           end),
         {:ok, _} <- discerner(Map.get(input, :discerner)) do
      {:ok, struct!(__MODULE__, input)}
    else
      _ -> {:error, Error.new(:invalid_joiner_config)}
    end
  end

  def new(_), do: {:error, Error.new(:invalid_joiner_config)}

  @doc false
  @spec encode(term()) :: {:ok, map()} | {:error, Error.t()}
  def encode(%__MODULE__{} = config) when map_size(config) == 8 do
    with {:ok, valid} <- new(Map.from_struct(config)),
         {:ok, identity} <- discerner(valid.discerner),
         do: {:ok, Map.put(Map.from_struct(valid), :discerner, identity)}
  end

  def encode(_), do: {:error, Error.new(:invalid_joiner_config)}

  defp discerner(nil), do: {:ok, nil}
  defp discerner(%JoinerIdentity{kind: :discerner} = identity), do: JoinerIdentity.encode(identity)
  defp discerner(_), do: {:error, Error.new(:invalid_joiner_identity)}
end
