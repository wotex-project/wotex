defmodule Wotex.Runtime.Limits do
  @moduledoc """
  Fixed admission limits for bounded Runtime-owned values and selection scans.

  These limits bound only data the Runtime admits or scans itself. Interaction
  payload size, nested metadata values, callback duration and transport
  allocation remain consumer and binding responsibilities.

  | Limit | Maximum |
  | --- | ---: |
  | request id bytes | 256 |
  | top-level metadata entries | 64 |
  | binding profiles per ConsumedThing or selection | 32 |
  | Forms scanned for one interaction | 128 |
  """

  @limits %{
    request_id_bytes: 256,
    metadata_entries: 64,
    binding_profiles: 32,
    forms_per_interaction: 128
  }

  @type name ::
          :request_id_bytes | :metadata_entries | :binding_profiles | :forms_per_interaction

  @doc "Returns every fixed Runtime admission limit."
  @spec all() :: %{
          request_id_bytes: 256,
          metadata_entries: 64,
          binding_profiles: 32,
          forms_per_interaction: 128
        }
  def all, do: @limits

  @doc "Returns one fixed Runtime admission limit."
  @spec maximum(name()) :: pos_integer()
  def maximum(name), do: Map.fetch!(@limits, name)

  @doc false
  @spec list_within?(list(), non_neg_integer()) :: boolean()
  def list_within?(values, maximum) when is_list(values) and maximum >= 0,
    do: within?(values, maximum)

  defp within?([], _remaining), do: true
  defp within?([_value | _rest], 0), do: false
  defp within?([_value | rest], remaining), do: within?(rest, remaining - 1)
end
