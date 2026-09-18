defmodule Wotex.BACnet.COVWire do
  @moduledoc """
  Performs one SubscribeCOV control exchange through the verified SDK wrapper.

  `Wotex.BACnet.COVOwner` supplies the request, subscriber identifier, absolute
  deadline, and whether this is cancellation. The pure COV codec constructs the
  APDU, and `Wotex.BACnet.StackClient` checks admission before transmission.
  Configured peer receive limits govern the exchange.

  The response must acknowledge the requested control service; errors pass
  through the typed BACstack response boundary. This function runs inside the
  owner's cancellable worker and does not independently schedule renewal or
  decide that a subscription is established.
  """

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
  end
end
