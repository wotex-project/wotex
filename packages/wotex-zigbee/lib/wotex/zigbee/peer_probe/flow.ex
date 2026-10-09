defmodule Wotex.Zigbee.PeerProbe.Flow do
  @moduledoc false

  alias Wotex.Zigbee.{ChannelMigration, Command, Error, Event, Frame, Reply, ZCL}
  alias Wotex.Zigbee.ChannelMigration.Result

  @type t :: %{epoch: reference(), peers: [Result.peer_result()], index: non_neg_integer()}

  @doc false
  @spec new([ChannelMigration.peer()], reference(), [byte()]) :: t()
  def new(selected, epoch, tokens) do
    peers =
      Enum.zip_with(selected, tokens, fn peer, token ->
        %{
          peer: peer,
          token: token,
          admission: nil,
          confirmation: nil,
          response: nil,
          attributes: nil,
          outcome: :unconfirmed,
          issue: nil
        }
      end)

    %{epoch: epoch, peers: peers, index: 0}
  end

  @doc false
  @spec current(t()) :: Result.peer_result() | nil
  def current(flow), do: Enum.at(flow.peers, flow.index)

  @doc false
  @spec command(t()) :: {:ok, Frame.t()} | {:error, Error.t()}
  def command(flow) do
    %{peer: peer, token: token} = current(flow)

    with {:ok, data} <- ZCL.read_attributes([0], token, :client_to_server) do
      Command.data_request(
        peer.route_address,
        peer.destination_endpoint,
        peer.source_endpoint,
        0,
        token,
        data
      )
    end
  end

  @doc false
  @spec admit(t(), Reply.t()) :: t()
  def admit(flow, reply), do: update(flow, &%{&1 | admission: reply})

  @doc false
  @spec offer(t(), Event.t()) :: {:matched, t()} | :unmatched
  def offer(flow, %Event{owner_epoch: epoch} = event) when epoch == flow.epoch do
    offer_current(flow, current(flow), event)
  end

  def offer(_, _), do: :unmatched

  @doc false
  @spec advance(t()) :: {:waiting | :next | :done, t()}
  def advance(flow) do
    case current(flow) do
      %{admission: nil} -> {:waiting, flow}
      %{admission: %{status: status}} when status != 0 -> finish_peer(flow, :status_failure)
      %{confirmation: %{status: status}} when status != 0 -> finish_peer(flow, :status_failure)
      %{confirmation: nil} -> {:waiting, flow}
      %{response: nil} -> {:waiting, flow}
      %{attributes: attributes} -> finish_peer(flow, attribute_issue(attributes))
    end
  end

  @doc false
  @spec finish_peer(t(), Error.kind() | nil) :: {:next | :done, t()}
  def finish_peer(flow, issue) do
    flow = update(flow, &%{&1 | outcome: outcome(&1, issue), issue: issue})
    next = %{flow | index: flow.index + 1}
    {if(next.index == length(flow.peers), do: :done, else: :next), next}
  end

  @doc false
  @spec finish(t(), Error.kind() | nil) :: [Result.peer_result()]
  def finish(flow, issue) do
    Enum.with_index(flow.peers, fn peer, index ->
      if index >= flow.index,
        do: %{peer | outcome: outcome(peer, issue), issue: issue},
        else: peer
    end)
  end

  defp offer_current(
         flow,
         %{confirmation: nil, peer: peer, token: token},
         %Event{
           kind: :aps_confirm,
           endpoint: endpoint,
           transaction: token
         } = event
       )
       when endpoint == peer.source_endpoint,
       do: {:matched, update(flow, &%{&1 | confirmation: event})}

  defp offer_current(
         flow,
         %{response: nil, peer: peer, token: token},
         %Event{
           kind: :af_incoming,
           cluster: 0,
           source_address: route,
           source_endpoint: remote,
           endpoint: local,
           payload: payload
         } = event
       )
       when route == peer.route_address and remote == peer.destination_endpoint and
              local == peer.source_endpoint do
    case ZCL.decode_attributes(payload) do
      {:ok,
       %{command: :read_response, direction: :server_to_client, manufacturer: nil} = attributes}
      when attributes.sequence == token ->
        {:matched, update(flow, &%{&1 | response: event, attributes: attributes})}

      _ ->
        :unmatched
    end
  end

  defp offer_current(_, _, _), do: :unmatched

  defp outcome(_, issue) when issue not in [nil, :status_failure, :invalid_value], do: :unconfirmed
  defp outcome(%{admission: %{status: status}}, _) when status != 0, do: :ncp_rejected
  defp outcome(%{confirmation: %{status: status}}, _) when status != 0, do: :aps_failed

  defp outcome(%{admission: %{status: 0}, confirmation: %{status: 0}, response: %Event{}}, _),
    do: :responsive

  defp outcome(_, _), do: :unconfirmed

  defp attribute_issue(%{attributes: [%{id: 0, status: :success, type: 0x20, value: value}]})
       when is_integer(value) and value in 0..254, do: nil

  defp attribute_issue(_), do: :invalid_value

  defp update(flow, function),
    do: %{flow | peers: List.update_at(flow.peers, flow.index, function)}
end
