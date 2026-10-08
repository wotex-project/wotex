defmodule Wotex.Zigbee do
  @moduledoc """
  Explicit, bounded host for a TI ZNP Zigbee network co-processor.

  A consumer supplies a serial adapter, stable device identity and exact
  firmware version tuple through `Wotex.Zigbee.Config`. `open/1` negotiates
  `SYS_VERSION` before returning an opaque handle. A long-lived consumer may
  supervise `child_spec/2` and obtain its handle with `handle/1`.

  The admitted software profile sends bounded ZDO descriptor requests and AF
  data requests. Their immediate SRSPs prove NCP admission only. Later ZDO,
  APS and application indications are separate bounded events. No implicit
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
    Command,
    Config,
    DataRequest,
    Downlinks,
    Error,
    Event,
    Handle,
    Interview,
    Owner,
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
