defmodule Wotex.BACnet.Bench.Values do
  @moduledoc false

  # Synthetic BACnet values and service APDUs. Object and Property identifiers
  # are standard (analog-value 1, present-value 85, object-name 77,
  # description 28); strings are deterministic UTF-8 text.

  alias BACnet.Protocol.APDU.{ComplexACK, ConfirmedServiceRequest}
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet.Value

  @object_type 2
  @instance 1
  @invoke_id 42

  @spec cases() :: [{String.t(), String.t(), term(), non_neg_integer()}]
  def cases do
    [
      {"Real present-value", "bacv:Real", 21.5, 85},
      {"64-byte object-name", "bacv:String", text(64), 77},
      {"1 KiB description", "bacv:String", text(1024), 28}
    ]
  end

  @spec text(pos_integer()) :: binary()
  def text(size), do: binary_part(:binary.copy("Zone 4 supply air ", div(size, 18) + 1), 0, size)

  @spec encode!(term(), String.t()) :: Encoding.t()
  def encode!(value, type) do
    {:ok, encoded} = Value.encode(value, %{"@type" => type})
    encoded
  end

  @spec read_request(non_neg_integer()) :: ConfirmedServiceRequest.t()
  def read_request(property), do: request(:read_property, selectors(property, []))

  @spec write_request(non_neg_integer(), tuple()) :: ConfirmedServiceRequest.t()
  def write_request(property, tag),
    do:
      request(
        :write_property,
        selectors(property, [{:constructed, {3, tag, 0}}, {:tagged, {4, <<8>>, 1}}])
      )

  @spec read_ack(non_neg_integer(), tuple()) :: ComplexACK.t()
  def read_ack(property, tag) do
    %ComplexACK{
      invoke_id: @invoke_id,
      sequence_number: nil,
      proposed_window_size: nil,
      service: :read_property,
      payload: selectors(property, [{:constructed, {3, tag, 0}}])
    }
  end

  @spec tag(term()) :: tuple()
  def tag(value) when is_float(value), do: {:real, value}
  def tag(value) when is_binary(value), do: {:character_string, value}

  defp request(service, parameters) do
    %ConfirmedServiceRequest{
      segmented_response_accepted: true,
      max_segments: 32,
      max_apdu: 1476,
      invoke_id: @invoke_id,
      sequence_number: nil,
      proposed_window_size: nil,
      service: service,
      parameters: parameters
    }
  end

  defp selectors(property, rest) do
    [
      {:tagged, {0, <<@object_type::10, @instance::22>>, 4}},
      {:tagged, {1, :binary.encode_unsigned(property), 1}} | rest
    ]
  end
end
