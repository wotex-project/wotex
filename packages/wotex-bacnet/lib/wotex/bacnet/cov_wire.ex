defmodule Wotex.BACnet.COVWire do
  @moduledoc false

  alias Wotex.BACnet.{BACstack, COV, COVRequest, Error, StackClient}

  @doc false
  @spec exchange(map(), COVRequest.t(), non_neg_integer(), integer(), boolean()) ::
          {:ok, :subscribed} | {:error, Error.t()}
  def exchange(config, request, identifier, deadline, cancel) do
    with {:ok, apdu} <- COV.request(request, identifier, cancel) do
      peer = config.peer_receive

      StackClient.exchange(
        config.client,
        config.destination,
        apdu,
        [
          max_apdu_length: peer.max_apdu,
          max_segments: peer.max_segments,
          segmentation_supported: peer.segmentation
        ],
        deadline
      )
      |> BACstack.control_response(apdu.service)
    end
  rescue
    _ -> {:error, Error.new(:transport_error)}
  catch
    :exit, _ -> {:error, Error.new(:connection_closed)}
  end
end
