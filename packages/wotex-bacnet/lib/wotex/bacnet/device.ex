defmodule Wotex.BACnet.Device do
  @moduledoc "A validated I-Am observation retaining its source without selecting a route."

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
