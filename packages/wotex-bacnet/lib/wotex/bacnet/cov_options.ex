defmodule Wotex.BACnet.COVOptions do
  @moduledoc false

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
