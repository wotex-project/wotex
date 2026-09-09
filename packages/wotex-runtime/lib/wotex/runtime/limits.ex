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

  `all/0` exposes the fixed contract, `maximum/1` retrieves a named ceiling, and
  `list_within?/2` checks list length without traversing beyond the permitted
  count. Binding implementations retain responsibility for their protocol and
  payload limits.
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

  defp within?([], _), do: true
  defp within?([_ | _], 0), do: false
  defp within?([_ | rest], remaining), do: within?(rest, remaining - 1)
end
