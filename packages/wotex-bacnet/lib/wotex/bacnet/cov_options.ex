defmodule Wotex.BACnet.COVOptions do
  @moduledoc """
  Admits the finite COV option map used by Runtime Property observations.

  Mapping supplies a Property COV message, an explicit receiver, and optional
  confirmation, lifetime, renewal, queue-length, duplicate-window, and increment
  fields. Unknown option keys fail before subscription establishment.

  `Wotex.BACnet.COVRequest` validates the merged request and applies its defaults.
  This helper does not infer a device instance from the first notification or
  turn a general BACnet service into an observation.
  """

  alias Wotex.BACnet.{COVRequest, Error}
  @keys [:confirmed, :lifetime, :renew, :max_queue_length, :duplicate_window_ms, :cov_increment]

  @doc false
  @spec request(term(), term(), pid()) :: {:ok, COVRequest.t()} | {:error, Error.t()}
  def request(%{type: :cov_property} = message, options, receiver)
      when is_map(options) and map_size(options) <= 6 do
    if Map.keys(options) -- @keys == [],
      do: COVRequest.new(Map.merge(message, options), receiver),
      else: {:error, Error.new(:invalid_cov_options)}
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_cov_options)}
end
