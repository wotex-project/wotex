defmodule Wotex.Thread.State do
  @moduledoc """
  Represents a non-secret OpenThread state snapshot.

  A snapshot records the device role, network name, Routing Locator (RLOC16),
  IPv6 and Thread enablement, and the owning session generation. It contains no
  Operational Dataset or credentials. `new/1` validates a supplied snapshot;
  it performs no SDK call and does not establish attachment or reachability.
  """

  alias Wotex.Thread.Error

  @fields [:role, :network_name, :rloc16, :ipv6_enabled, :thread_enabled, :generation]
  @roles [:disabled, :detached, :child, :router, :leader]
  @enforce_keys @fields
  defstruct @fields

  @typedoc "A validated snapshot from one explicitly owned session generation."
  @type t :: %__MODULE__{
          role: :disabled | :detached | :child | :router | :leader,
          network_name: String.t() | nil,
          rloc16: 0..65_535 | nil,
          ipv6_enabled: boolean(),
          thread_enabled: boolean(),
          generation: non_neg_integer()
        }

  @doc "Validates an exact snapshot map without acquiring resources."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(fields) when is_map(fields) and map_size(fields) == 6 do
    if Enum.all?(@fields, &Map.has_key?(fields, &1)) do
      state = struct!(__MODULE__, fields)
      with :ok <- validate(state), do: {:ok, state}
    else
      {:error, Error.new(:invalid_state)}
    end
  end

  def new(_), do: {:error, Error.new(:invalid_state)}

  @doc "Revalidates every field of a public snapshot, including forged structs."
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(%__MODULE__{} = state) when map_size(state) == 7 do
    if Enum.all?(@fields, &Map.has_key?(state, &1)) and state.role in @roles and
         network_name?(state.network_name) and locator?(state.rloc16) and
         is_boolean(state.ipv6_enabled) and is_boolean(state.thread_enabled) and
         is_integer(state.generation) and state.generation >= 0 and
         (not state.thread_enabled or state.ipv6_enabled) and
         state.role == :disabled == not state.thread_enabled do
      :ok
    else
      {:error, Error.new(:invalid_state)}
    end
  end

  def validate(_), do: {:error, Error.new(:invalid_state)}

  defp network_name?(nil), do: true

  defp network_name?(name) when is_binary(name) and byte_size(name) in 1..16,
    do: String.valid?(name) and not Regex.match?(~r/[\x00-\x1f\x7f]/, name)

  defp network_name?(_), do: false
  defp locator?(nil), do: true
  defp locator?(value), do: is_integer(value) and value in 0..65_535
end
