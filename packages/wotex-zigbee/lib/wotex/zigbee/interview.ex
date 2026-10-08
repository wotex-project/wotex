defmodule Wotex.Zigbee.Interview do
  @moduledoc """
  Inert policy for one bounded identity, descriptor and Basic-attribute interview.

  The consumer supplies an expected raw EUI-64, its candidate unicast route
  and an already registered local AF endpoint. The owner queries identity,
  node, active endpoints and one simple descriptor per distinct valid endpoint.
  It reads selected Basic attributes only from Home Automation profile
  `0x0104` endpoints advertising Basic input cluster `0x0000`.

  The finite Basic profile follows ZCL document 07-5123 revision 8:
  ZCLVersion (`0x0000`), ManufacturerName (`0x0004`), ModelIdentifier (`0x0005`)
  and ClusterRevision (`0xFFFD`). Strings remain untrusted bytes. No joining,
  configuration, binding, enrollment or retry follows from this value.

  `max_endpoints` bounds the complete advertised list, including duplicates;
  its default is 16 and its maximum is 77. All steps share one caller deadline.
  Identity matching does not authenticate a peer or authorize Thing admission.
  """

  alias Wotex.Zigbee.Error

  @enforce_keys [:peer_ieee, :route_address, :source_endpoint]
  defstruct [
    :peer_ieee,
    :route_address,
    :source_endpoint,
    max_endpoints: 16,
    basic_attributes: [0x0000, 0x0004, 0x0005, 0xFFFD]
  ]

  @type t :: %__MODULE__{
          peer_ieee: <<_::64>>,
          route_address: 0..0xFFF7,
          source_endpoint: 1..240,
          max_endpoints: 1..77,
          basic_attributes: [0x0000 | 0x0004 | 0x0005 | 0xFFFD]
        }

  @allowed ~w(peer_ieee route_address source_endpoint max_endpoints basic_attributes)a

  @doc "Builds a pure interview policy, rejecting missing, duplicate and unknown options."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(options) when is_list(options) do
    if Keyword.keyword?(options) and length(options) == length(Enum.uniq(Keyword.keys(options))) and
         Enum.all?(Keyword.keys(options), &(&1 in @allowed)) do
      request = struct(__MODULE__, options)
      if valid?(request), do: {:ok, request}, else: invalid()
    else
      invalid()
    end
  end

  def new(_), do: invalid()

  @doc "Revalidates a copied policy at the receiver boundary."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = request) do
    map_size(request) == 6 and valid_ieee?(request.peer_ieee) and
      in_range?(request.route_address, 0, 0xFFF7) and
      in_range?(request.source_endpoint, 1, 240) and
      in_range?(request.max_endpoints, 1, 77) and
      is_list(request.basic_attributes) and length(request.basic_attributes) in 1..4 and
      length(request.basic_attributes) == length(Enum.uniq(request.basic_attributes)) and
      Enum.all?(request.basic_attributes, &(&1 in [0, 4, 5, 0xFFFD]))
  end

  def valid?(_), do: false

  defp valid_ieee?(<<value::64>>), do: value not in [0, 0xFFFFFFFFFFFFFFFF]
  defp valid_ieee?(_), do: false
  defp in_range?(value, first, last), do: is_integer(value) and value in first..last
  defp invalid, do: {:error, %Error{kind: :invalid_value, operation: :interview}}
end
