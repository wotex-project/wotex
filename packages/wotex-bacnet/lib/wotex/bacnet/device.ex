defmodule Wotex.BACnet.Device do
  @moduledoc """
  Represents one validated I-Am observation with its original IPv4 source.

  The exact value records source address and port, device instance, maximum
  APDU size, segmentation capability, and vendor identifier. `new/1` validates
  an existing struct or a map with precisely those fields. Unknown fields,
  invalid numeric bounds, and unsupported segmentation values return
  `:invalid_device`.

  `Wotex.BACnet.NativeDiscovery` returns these values in source-and-instance
  order. An observation describes what the sender advertised; it does not
  establish trust, choose a destination for later operations, or modify session
  receive limits. The consumer configures any subsequent connection explicitly.

  ## Examples

      iex> {:ok, device} = Wotex.BACnet.Device.new(%{source: {{192, 0, 2, 1}, 47808}, instance: 42, max_apdu: 1476, segmentation: :no_segmentation, vendor_id: 0})
      iex> {device.source, device.instance}
      {{{192, 0, 2, 1}, 47808}, 42}
  """

  alias BACnet.Protocol.{APDU, ObjectIdentifier}
  alias BACnet.Protocol.Services.IAm
  alias Wotex.BACnet.Error

  @fields [:source, :instance, :max_apdu, :segmentation, :vendor_id]
  @enforce_keys @fields
  defstruct @fields

  @type source :: {{byte(), byte(), byte(), byte()}, 1..65_535}
  @type t :: %__MODULE__{
          source: source(),
          instance: 0..4_194_302,
          max_apdu: 1..65_535,
          segmentation:
            :segmented_both | :segmented_transmit | :segmented_receive | :no_segmentation,
          vendor_id: 0..65_535
        }

  @doc "Constructs or revalidates an exact bounded discovery observation."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = device), do: new(Map.from_struct(device))

  def new(input) when is_map(input) and map_size(input) == 5 do
    if Map.keys(input) -- @fields == [] and valid_fields?(input),
      do: {:ok, struct!(__MODULE__, input)},
      else: {:error, Error.new(:invalid_device)}
  end

  def new(_), do: {:error, Error.new(:invalid_device)}

  @doc false
  @spec from_apdu(term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def from_apdu(
        source,
        %APDU.UnconfirmedServiceRequest{
          service: :i_am,
          parameters: [_, _, _, _]
        } = apdu
      ) do
    case IAm.from_apdu(apdu) do
      {:ok, %IAm{device: %ObjectIdentifier{type: :device, instance: instance}} = iam} ->
        new(%{
          source: source,
          instance: instance,
          max_apdu: iam.max_apdu,
          segmentation: iam.segmentation_supported,
          vendor_id: iam.vendor_id
        })

      _ ->
        {:error, Error.new(:invalid_device)}
    end
  rescue
    _ -> {:error, Error.new(:invalid_device)}
  end

  def from_apdu(_, _), do: {:error, Error.new(:invalid_device)}

  @doc false
  @spec valid_source?(term()) :: boolean()
  def valid_source?({{a, b, c, d}, port}),
    do: Enum.all?([a, b, c, d], &uint?(&1, 255)) and uint?(port, 65_535) and port > 0

  def valid_source?(_), do: false

  defp valid_fields?(input) do
    valid_source?(input.source) and uint?(input.instance, 4_194_302) and
      uint?(input.max_apdu, 65_535) and input.max_apdu > 0 and uint?(input.vendor_id, 65_535) and
      input.segmentation in [
        :segmented_both,
        :segmented_transmit,
        :segmented_receive,
        :no_segmentation
      ]
  end

  defp uint?(value, maximum), do: is_integer(value) and value in 0..maximum
end
