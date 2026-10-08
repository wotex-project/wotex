defmodule Wotex.Zigbee.Interview.Flow do
  @moduledoc false

  alias Wotex.Zigbee.{Command, Error, Event, Frame, Interview, Reply, ZCL}
  alias Wotex.Zigbee.Interview.Result

  @type t :: %{
          request: Interview.t(),
          epoch: reference(),
          stage: Result.stage() | :done,
          token: byte() | nil,
          admission: Reply.t() | nil,
          response: Event.t() | nil,
          confirmation: Event.t() | nil,
          attributes: ZCL.decoded() | nil,
          steps: [Result.step()],
          endpoints: [byte()],
          basic_endpoints: [byte()],
          identity_matches: boolean()
        }

  @doc false
  @spec new(Interview.t(), reference()) :: t()
  def new(%Interview{} = request, epoch) do
    %{
      request: request,
      epoch: epoch,
      stage: :identity,
      token: nil,
      admission: nil,
      response: nil,
      confirmation: nil,
      attributes: nil,
      steps: [],
      endpoints: [],
      basic_endpoints: [],
      identity_matches: false
    }
  end

  @doc false
  @spec command(t()) :: {:ok, Frame.t()} | {:error, Error.t()}
  def command(%{stage: :identity, request: request}),
    do: Command.ieee_address(request.route_address)

  def command(%{stage: :node, request: request}),
    do: Command.node_descriptor(request.route_address)

  def command(%{stage: :active, request: request}),
    do: Command.active_endpoints(request.route_address)

  def command(%{stage: {:simple, endpoint}, request: request}),
    do: Command.simple_descriptor(request.route_address, endpoint)

  def command(%{stage: {:basic, endpoint}, request: request, token: token}) do
    with {:ok, data} <- ZCL.read_attributes(request.basic_attributes, token, :client_to_server) do
      Command.data_request(request.route_address, endpoint, request.source_endpoint, 0, token, data)
    end
  end

  @doc false
  @spec offer(t(), Event.t()) :: {:matched, t()} | :unmatched
  def offer(
        %{stage: {:basic, _}, confirmation: nil} = flow,
        %Event{kind: :aps_confirm, endpoint: endpoint, transaction: token} = event
      )
      when endpoint == flow.request.source_endpoint and token == flow.token,
      do: {:matched, %{flow | confirmation: event}}

  def offer(%{response: nil} = flow, %Event{} = event) do
    case response(flow, event) do
      {:ok, attributes} -> {:matched, %{flow | response: event, attributes: attributes}}
      :unmatched -> :unmatched
    end
  end

  def offer(_, _), do: :unmatched

  @doc false
  @spec admit(t(), Reply.t()) :: t()
  def admit(flow, %Reply{} = reply), do: %{flow | admission: reply}

  @doc false
  @spec advance(t()) :: {:waiting | :next, t()} | {:done, Result.t()}
  def advance(%{admission: nil} = flow), do: {:waiting, flow}

  def advance(%{admission: %{status: status}} = flow) when status != 0,
    do: {:done, finish(flow, :ncp_rejected)}

  def advance(%{stage: {:basic, _}, confirmation: %{status: status}} = flow) when status != 0,
    do: next_basic(record(flow, [:aps_failure]))

  def advance(%{response: nil} = flow), do: {:waiting, flow}

  def advance(%{stage: {:basic, _}, confirmation: nil} = flow), do: {:waiting, flow}

  def advance(%{stage: :identity, response: event} = flow) do
    cond do
      event.status != 0 -> {:done, finish(flow, :status_failure)}
      event.zdo.peer_ieee != flow.request.peer_ieee -> {:done, finish(flow, :identity_mismatch)}
      true -> {:next, reset(record(%{flow | identity_matches: true}, []), :node)}
    end
  end

  def advance(%{stage: :node, response: event} = flow),
    do: {:next, reset(record(flow, status_issues(event)), :active)}

  def advance(%{stage: :active, response: event} = flow) do
    endpoints = event.zdo.endpoints

    cond do
      event.status != 0 ->
        {:done, finish(flow, :status_failure)}

      length(endpoints) > flow.request.max_endpoints ->
        {:done, finish(flow, :overload)}

      true ->
        valid =
          endpoints
          |> Enum.filter(&(&1 in 1..240))
          |> Enum.uniq()

        issues = if length(valid) == length(Enum.uniq(endpoints)), do: [], else: [:invalid_endpoint]
        next_simple(%{record(flow, issues) | endpoints: valid})
    end
  end

  def advance(%{stage: {:simple, endpoint}, response: event} = flow) do
    basic =
      if event.status == 0 and event.zdo.descriptor.profile == 0x0104 and
           0 in event.zdo.descriptor.input_clusters,
         do: [endpoint | flow.basic_endpoints],
         else: flow.basic_endpoints

    next_simple(%{record(flow, status_issues(event)) | basic_endpoints: basic})
  end

  def advance(%{stage: {:basic, _}} = flow), do: next_basic(record(flow, basic_issues(flow)))

  @doc false
  @spec finish(t(), atom()) :: Result.t()
  def finish(flow, issue) do
    flow = if flow.stage == :done, do: flow, else: record(flow, [issue])
    result(flow)
  end

  defp response(
         %{stage: :identity, request: request},
         %Event{kind: :zdo_ieee_address, zdo: %{network_address: route}}
       )
       when route == request.route_address, do: {:ok, nil}

  defp response(
         %{stage: :node, request: request},
         %Event{kind: :zdo_node_descriptor, zdo: %{source_address: route, network_address: route}}
       )
       when route == request.route_address, do: {:ok, nil}

  defp response(
         %{stage: :active, request: request},
         %Event{kind: :zdo_active_endpoints, zdo: %{source_address: route, network_address: route}}
       )
       when route == request.route_address, do: {:ok, nil}

  defp response(
         %{stage: {:simple, endpoint}, request: request},
         %Event{
           kind: :zdo_simple_descriptor,
           zdo: %{source_address: route, network_address: route, descriptor: descriptor}
         }
       )
       when route == request.route_address do
    if descriptor == nil or descriptor.endpoint == endpoint, do: {:ok, nil}, else: :unmatched
  end

  defp response(
         %{stage: {:basic, endpoint}, request: request, token: token},
         %Event{
           kind: :af_incoming,
           cluster: 0,
           source_address: route,
           source_endpoint: endpoint,
           endpoint: local,
           payload: payload
         }
       )
       when route == request.route_address and local == request.source_endpoint do
    case ZCL.decode_attributes(payload) do
      {:ok, %{command: :read_response, direction: :server_to_client, manufacturer: nil} = decoded}
      when decoded.sequence == token ->
        {:ok, decoded}

      _ ->
        :unmatched
    end
  end

  defp response(_, _), do: :unmatched

  defp next_simple(%{endpoints: [endpoint | rest]} = flow),
    do: {:next, reset(%{flow | endpoints: rest}, {:simple, endpoint})}

  defp next_simple(flow),
    do: next_basic(%{flow | basic_endpoints: Enum.reverse(flow.basic_endpoints)})

  defp next_basic(%{basic_endpoints: [endpoint | rest]} = flow),
    do: {:next, reset(%{flow | basic_endpoints: rest}, {:basic, endpoint})}

  defp next_basic(flow), do: {:done, result(%{flow | stage: :done})}

  defp reset(flow, stage),
    do: %{
      flow
      | stage: stage,
        token: nil,
        admission: nil,
        response: nil,
        confirmation: nil,
        attributes: nil
    }

  defp record(flow, issues) do
    step = %{
      stage: flow.stage,
      admission: flow.admission,
      response: flow.response,
      confirmation: flow.confirmation,
      attributes: flow.attributes,
      issues: issues
    }

    %{flow | steps: [step | flow.steps]}
  end

  defp result(flow) do
    %Result{
      peer_ieee: flow.request.peer_ieee,
      route_address: flow.request.route_address,
      owner_epoch: flow.epoch,
      identity_matches: flow.identity_matches,
      outcome: if(Enum.all?(flow.steps, &(&1.issues == [])), do: :complete, else: :partial),
      steps: Enum.reverse(flow.steps)
    }
  end

  defp status_issues(%Event{status: 0}), do: []
  defp status_issues(_), do: [:status_failure]

  defp basic_issues(flow) do
    attributes = flow.attributes.attributes
    ids = Enum.map(attributes, & &1.id)
    expected = flow.request.basic_attributes

    []
    |> issue_if(length(ids) != length(Enum.uniq(ids)), :duplicate_attribute)
    |> issue_if(Enum.any?(ids, &(&1 not in expected)), :unexpected_attribute)
    |> issue_if(Enum.any?(expected, &(&1 not in ids)), :missing_attribute)
    |> issue_if(Enum.any?(attributes, &(&1.status != :success)), :attribute_failure)
    |> issue_if(Enum.any?(attributes, &(not basic_value?(&1))), :invalid_value)
    |> Enum.reverse()
  end

  defp basic_value?(%{status: {:error, _}}), do: true
  defp basic_value?(%{id: 0, type: 0x20, value: value}), do: value in 0..254
  defp basic_value?(%{id: 0xFFFD, type: 0x21, value: value}), do: value in 1..0xFFFE

  defp basic_value?(%{id: id, type: 0x42, value: value}) when id in [4, 5],
    do: is_binary(value) and byte_size(value) <= 32 and String.valid?(value)

  defp basic_value?(_), do: false

  defp issue_if(issues, true, issue), do: [issue | issues]
  defp issue_if(issues, false, _), do: issues
end
