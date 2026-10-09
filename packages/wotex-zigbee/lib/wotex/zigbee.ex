defmodule Wotex.Zigbee do
  @moduledoc """
  Explicit, bounded host for a TI ZNP Zigbee network co-processor.

  A consumer supplies a serial adapter, stable device identity and exact
  firmware version tuple through `Wotex.Zigbee.Config`. `open/1` negotiates
  `SYS_VERSION` before returning an opaque handle. A long-lived consumer may
  supervise `child_spec/2` and obtain its handle with `handle/1`.

  The admitted software profile sends bounded ZDO descriptor requests, AF
  data requests, explicit Bind/Unbind, credentialed joining and channel migration.
  Their immediate SRSPs prove NCP admission only. Later ZDO, APS and
  application indications are separate bounded events. No implicit
  network formation, reset, restore or retry occurs.

  `Wotex.Zigbee.DataRequest` keeps an interviewed EUI-64 peer identity and
  caller correlation separate from the transient 16 bit route sent to ZNP.
  The caller verifies that route mapping after rejoin and matches later
  indications; this host cannot infer durable identity from a short address.

  `Wotex.Zigbee.Command` contains no raw public command escape hatch.
  Product interpretation, authorization, network credentials and physical
  effect truth remain with the consumer.
  """

  alias Wotex.Zigbee.{
    Binding,
    ChannelMigration,
    Command,
    Config,
    Credentials,
    DataRequest,
    Downlinks,
    Error,
    Event,
    Handle,
    Interview,
    KeyRotation,
    Network,
    Owner,
    PermitJoin,
    Reply,
    Routes
  }

  @type result(value) :: {:ok, value} | {:error, Error.t()}

  @doc """
  Starts, negotiates and links one coordinator owner before delivering its handle.

  The startup deadline includes handle handoff. This caller owns the returned
  lifetime; its normal or abnormal exit closes the owner. Use `child_spec/2`
  for consumer supervision. Copying a handle does not transfer ownership.
  """
  @spec open(Config.t()) :: result(Handle.t())
  def open(%Config{} = config), do: Owner.open(config)

  def open(_), do: {:error, %Error{kind: :invalid_config, operation: :open}}

  @doc "Builds a transient child specification; consumers may override its restart policy."
  @spec child_spec(Config.t(), keyword()) :: Supervisor.child_spec()
  def child_spec(%Config{} = config, options \\ []),
    do: Supervisor.child_spec({Owner, config}, Keyword.put_new(options, :restart, :transient))

  @doc "Returns a handle from a negotiated, supervised owner."
  @spec handle(pid()) :: result(Handle.t())
  def handle(owner), do: Owner.handle(owner)

  @doc "Stops this owner; closing the serial adapter invalidates its epoch."
  @spec close(Handle.t()) :: :ok | {:error, Error.t()}
  def close(handle), do: Owner.call(handle, :close, [])

  @doc """
  Inspects one candidate under a single deadline without joining or configuring it.

  The owner keeps immediate admission, later descriptors, APS confirmation and
  selected Basic records separate in `Wotex.Zigbee.Interview.Result`. An admitted
  workflow returns a partial result on rejection, timeout or serial loss.
  Timeout or caller death ends the epoch; unrelated events remain drainable.
  The route must have no earlier ZDO query in this epoch. A later interview of
  a reused route requires a newly negotiated owner, without resetting the NCP.
  """
  @spec interview(Handle.t(), Interview.t(), pos_integer()) :: result(Interview.Result.t())
  def interview(handle, request, timeout), do: Owner.call(handle, :interview, [request, timeout])

  @doc """
  Performs one explicitly authorized Bind/Unbind under current source custody.

  Keep NCP admission and the matched peer status separate in
  `Wotex.Zigbee.Binding.Result`. The receiver validates the complete request
  and current route, clamps the absolute deadline to custody expiry and owns
  one caller monitor through both observations. Rejection before dispatch
  leaves the owner usable; timeout, caller loss or serial failure after
  dispatch ends the epoch without resetting the network.

  This MT callback lacks echoed binding fields and an independent host token.
  Each route/operation pair is retired on dispatch or callback observation;
  repeating it requires a fresh owner and custody. The finite retirement table
  admits 256 pairs. Consumer destination/battery qualification and actual
  reporting remain separate; no retry, automatic binding or interval change
  occurs.
  """
  @spec change_binding(Handle.t(), Routes.t(), Binding.t(), pos_integer()) ::
          result(Binding.Result.t())
  def change_binding(handle, routes, request, timeout),
    do: Owner.call(handle, :binding, [routes, request, timeout])

  @doc """
  Reads the coordinator's bounded device and network metadata under one deadline.

  `Wotex.Zigbee.Network.Snapshot` preserves both exact replies, observation
  times, failed status, partial issues and changed route/state. The owner
  holds one admission slot and caller monitor across both queries. Unrelated
  indications remain queued. Expiry before dispatch leaves the owner usable;
  timeout, malformed reply, serial failure or caller loss after dispatch
  ends the epoch. No query reads keys, opens joining or changes the network.
  Sequential matching metadata supplies no atomic or credential continuity
  proof. Qualify the exact firmware and consumer custody separately.
  """
  @spec inspect_network(Handle.t(), pos_integer()) :: result(Network.Snapshot.t())
  def inspect_network(handle, timeout), do: Owner.call(handle, :network, [timeout])

  @doc """
  Explicitly requests local permit-join or closure through consumer credential custody.

  Fresh device/network readings must match `Wotex.Zigbee.PermitJoin` before
  the supplied `Wotex.Zigbee.Credentials` port authorizes the exact request.
  Its finite horizon shortens dispatch time by the requested duration. One
  caller monitor and original deadline cover inspection, authorization and
  command admission; no key bytes enter requests or results.

  `Wotex.Zigbee.PermitJoin.Result` retains NCP admission only. Management
  responses and local change indications remain independently drainable;
  they lack a request token. Zero requests closure and 1–254 seconds request
  bounded joining. This profile does not broadcast, form a network, restore
  counters, change credentials or infer successful enrollment or closure.
  """
  @spec permit_join(Handle.t(), Credentials.t(), PermitJoin.t(), pos_integer()) ::
          result(PermitJoin.Result.t())
  def permit_join(handle, credentials, request, timeout),
    do: Owner.call(handle, :permit_join, [credentials, request, timeout])

  @doc """
  Changes channel explicitly and observes a bounded, currently custodied peer cohort.

  One deadline covers fresh expected-network metadata, consumer credential
  authorization, one broadcast/local-copy request, one qualified settling
  delay, target-channel metadata and one Basic read per selected peer. Each
  probe uses a fresh retired AF/ZCL token. A missing application observation
  may finish that peer and proceed; an unanswered SREQ ends the epoch because
  its uncorrelated reply cannot be reused safely.

  `Wotex.Zigbee.ChannelMigration.Result` retains local and per-peer partial
  observations, original security flags and unprobed peers. It does not infer
  whole-network migration or delivery to sleepy devices. Any administrative
  dispatch ends this owner epoch after observations. Reopen and adopt fresh
  custody before further operations. No rollback, retry, rekey or reset occurs.
  The consumer qualifies firmware update-ID headroom, network-manager support,
  administrative pacing, credentials and the requested settling delay.
  """
  @spec migrate_channel(
          Handle.t(),
          Credentials.t(),
          Routes.t(),
          ChannelMigration.t(),
          pos_integer()
        ) ::
          result(ChannelMigration.Result.t())
  def migrate_channel(handle, credentials, routes, request, timeout),
    do: Owner.call(handle, :channel_migration, [credentials, routes, request, timeout])

  @doc """
  Explicitly updates and switches a network key through private consumer custody.

  Fresh network metadata and current cohort custody precede update authorization.
  A one-use owner-only callback sends the consumer's 16-byte key; no key enters
  requests, results or stored owner state. After the qualified distribution
  delay, fresh metadata and separate switch authorization precede one switch.
  The receiver reserves both delays within finite horizons and retains one
  original deadline and caller monitor through post-switch peer observations.

  `Wotex.Zigbee.KeyRotation.Result` retains separate admissions, metadata and
  per-peer partial observations. Basic responses identify no key sequence;
  activation stays unconfirmed pending independent consumer qualification.
  Any key-write attempt ends the epoch after observations, including failed
  sends that can still change local key state. No rollback, retry or reset occurs.
  """
  @spec rotate_key(Handle.t(), Credentials.t(), Routes.t(), KeyRotation.t(), pos_integer()) ::
          result(KeyRotation.Result.t())
  def rotate_key(handle, credentials, routes, request, timeout),
    do: Owner.call(handle, :key_rotation, [credentials, routes, request, timeout])

  @doc "Queries one route's IEEE address; NCP admission and its later identity response are distinct."
  @spec ieee_address(Handle.t(), non_neg_integer(), pos_integer()) :: result(Reply.t())
  def ieee_address(handle, address, timeout) do
    with {:ok, frame} <- Command.ieee_address(address) do
      Owner.call(handle, :command, [frame, timeout])
    end
  end

  @doc "Requests one route's node descriptor; the later ZDO response is a distinct event."
  @spec node_descriptor(Handle.t(), non_neg_integer(), pos_integer()) :: result(Reply.t())
  def node_descriptor(handle, address, timeout) do
    with {:ok, frame} <- Command.node_descriptor(address) do
      Owner.call(handle, :command, [frame, timeout])
    end
  end

  @doc "Requests active endpoints; the later ZDO response is a distinct event."
  @spec active_endpoints(Handle.t(), non_neg_integer(), pos_integer()) :: result(Reply.t())
  def active_endpoints(handle, address, timeout) do
    with {:ok, frame} <- Command.active_endpoints(address) do
      Owner.call(handle, :command, [frame, timeout])
    end
  end

  @doc "Requests one simple descriptor; the later ZDO response is a distinct event."
  @spec simple_descriptor(Handle.t(), non_neg_integer(), pos_integer(), pos_integer()) ::
          result(Reply.t())
  def simple_descriptor(handle, address, endpoint, timeout) do
    with {:ok, frame} <- Command.simple_descriptor(address, endpoint) do
      Owner.call(handle, :command, [frame, timeout])
    end
  end

  @doc """
  Sends one bounded AF data request without inferring an over-the-air result.

  The transaction byte distinguishes a later APS confirmation; the consumer
  allocates it under its correlation policy. The payload may hold a ZCL
  command encoded with `Wotex.Zigbee.ZCL`.
  """
  @spec send_data(Handle.t(), DataRequest.t(), pos_integer()) :: result(Reply.t())
  def send_data(handle, %DataRequest{} = request, timeout) do
    if DataRequest.valid?(request) do
      with {:ok, frame} <-
             Command.data_request(
               request.route_address,
               request.destination_endpoint,
               request.source_endpoint,
               request.cluster,
               request.transaction,
               request.data,
               radius: request.radius,
               aps_ack: request.aps_ack,
               aps_security: request.aps_security
             ) do
        Owner.call(handle, :command, [frame, timeout])
      end
    else
      {:error, %Error{kind: :invalid_command, operation: :request}}
    end
  end

  def send_data(_, _, _),
    do: {:error, %Error{kind: :invalid_command, operation: :request}}

  @doc """
  Sends through the consumer's current adopted route table.

  The receiver checks owner epoch, identity, route and custody expiry before
  serial I/O, and limits the operation deadline to the custody expiry. This
  checks host mapping only; the consumer still authorizes the operation.
  """
  @spec send_routed_data(Handle.t(), Routes.t(), DataRequest.t(), pos_integer()) ::
          result(Reply.t())
  def send_routed_data(handle, routes, request, timeout),
    do: Owner.call(handle, :routed, [routes, request, timeout])

  @doc """
  Dispatches one inert queue delivery within its supplied absolute deadline.

  The receiver revalidates the delivery, owner epoch and current route custody
  and cannot renew its lifetime across mailbox waits. Expiry before writing
  leaves the owner usable; expiry after writing ends the epoch. The reply is
  NCP admission only. Consumer authorization and wakefulness remain separate.
  """
  @spec send_queued_data(Handle.t(), Routes.t(), Downlinks.delivery(), pos_integer()) ::
          result(Reply.t())
  def send_queued_data(handle, routes, delivery, timeout),
    do: Owner.call(handle, :queued, [routes, delivery, timeout])

  @doc """
  Sends the legacy route-only AF call; consumers retain peer identity and
  correlation outside this function. Prefer `send_data/3` with `DataRequest`.
  """
  @spec send_data(
          Handle.t(),
          non_neg_integer(),
          pos_integer(),
          pos_integer(),
          non_neg_integer(),
          non_neg_integer(),
          binary(),
          pos_integer(),
          keyword()
        ) ::
          result(Reply.t())
  def send_data(
        handle,
        address,
        destination_endpoint,
        source_endpoint,
        cluster,
        transaction,
        data,
        timeout,
        options \\ []
      ) do
    with {:ok, frame} <-
           Command.data_request(
             address,
             destination_endpoint,
             source_endpoint,
             cluster,
             transaction,
             data,
             options
           ) do
      Owner.call(handle, :command, [frame, timeout])
    end
  end

  @doc "Drains at most `count` indications and reports serial overflow explicitly."
  @spec drain_events(Handle.t(), pos_integer()) ::
          result(%{
            events: [Event.t()],
            dropped: non_neg_integer(),
            framing_faults: non_neg_integer()
          })
  def drain_events(handle, count), do: Owner.call(handle, :drain, [count])
end
