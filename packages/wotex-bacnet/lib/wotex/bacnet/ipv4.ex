defmodule Wotex.BACnet.IPv4 do
  @moduledoc """
  Owns an isolated BACnet/IP transport for a `Wotex.BACnet.Session`.

  `Wotex.BACnet.IPv4` implements `Wotex.BACnet.Client` by starting a bounded
  BACstack process group through `Wotex.BACnet.StackOwner`. Connection options
  identify the local interface, UDP port, destination, and request timeout.
  Local and destination ports accept the explicit range 1 through 65535.
  Requests are delegated to BACstack with Application Protocol Data Unit
  (APDU) retries configured to zero, and
  `disconnect/1` closes the exact process group created for the session.

  ## Network boundary

  Startup occurs only after an explicit `Wotex.BACnet.connect/1` call. The
  consumer still owns routing policy, interface availability, credentials, and
  supervision of the calling workflow. Upstream BACstack cannot bind a loopback
  interface; `local_ip: :none` is an explicit isolated-fixture option and is
  never selected as a default.
  """
  @behaviour Wotex.BACnet.Client
  alias Wotex.BACnet.{BACstack, Error, IngressTransport, StackOwner}

  @impl Wotex.BACnet.Client
  def connect(opts) when is_list(opts) do
    if admitted_options?(opts),
      do: connect_options(opts),
      else: {:error, Error.new(:invalid_options)}
  end

  def connect(_), do: {:error, Error.new(:invalid_options)}

  defp connect_options(opts) do
    timeout = Keyword.get(opts, :timeout, 5000)
    local_ip = Keyword.get(opts, :local_ip)
    local_port = Keyword.get(opts, :local_port, 47_809)

    with true <- valid_options?(local_ip, local_port, timeout),
         true <-
           IngressTransport.is_valid_destination(Keyword.get(opts, :destination)),
         {:ok, _} <-
           BACstack.configuration(
             discovery: Keyword.get(opts, :discovery),
             stack_client: self(),
             destination: Keyword.get(opts, :destination),
             peer_receive:
               Keyword.get(opts, :peer_receive, %{
                 max_apdu: 50,
                 max_segments: 1,
                 segmentation: :no_segmentation
               })
           ),
         {:ok, owner} <-
           StackOwner.start_link(
             local_ip: local_ip,
             local_port: local_port,
             timeout: timeout,
             owner: self()
           ),
         {:ok, client} <- StackOwner.client(owner),
         {:ok, stack} <-
           BACstack.connect_owned(
             [
               discovery: Keyword.get(opts, :discovery),
               stack_client: client,
               destination: Keyword.get(opts, :destination),
               writes: true,
               peer_receive:
                 Keyword.get(opts, :peer_receive, %{
                   max_apdu: 50,
                   max_segments: 1,
                   segmentation: :no_segmentation
                 }),
               receive_limits: %{max_apdu: 1476, max_segments: 32, max_bytes: 65_536}
             ],
             owner
           ) do
      {:ok, %{owner: owner, stack: stack}}
    else
      {:error, _} = error -> error
      _ -> {:error, Error.new(:invalid_options)}
    end
  end

  @impl Wotex.BACnet.Client
  def request(handle, message, timeout), do: BACstack.request(handle.stack, message, timeout)

  @impl Wotex.BACnet.Client
  def read_properties(%{stack: stack}, requests, timeout),
    do: BACstack.read_properties(stack, requests, timeout)

  def read_properties(_, _, _), do: {:error, Error.new(:invalid_properties)}

  @doc false
  @spec request_deadline(term(), term(), integer()) :: {:ok, term()} | {:error, Error.t()}
  def request_deadline(%{stack: stack}, message, deadline),
    do: BACstack.request_deadline(stack, message, deadline)

  def request_deadline(_, _, _), do: {:error, Error.new(:invalid_request)}

  @doc false
  @spec read_properties_deadline(term(), term(), integer()) :: {:ok, map()} | {:error, Error.t()}
  def read_properties_deadline(%{stack: stack}, requests, deadline),
    do: BACstack.read_properties_deadline(stack, requests, deadline)

  def read_properties_deadline(_, _, _), do: {:error, Error.new(:invalid_properties)}

  @impl Wotex.BACnet.Client
  def who_is(%{stack: stack}, low, high, timeout), do: BACstack.who_is(stack, low, high, timeout)
  def who_is(_, _, _, _), do: {:error, Error.new(:invalid_request)}

  @doc false
  @spec who_is_deadline(term(), term(), term(), integer(), integer()) ::
          {:ok, [Wotex.BACnet.Device.t()]} | {:error, Error.t()}
  def who_is_deadline(%{stack: stack}, low, high, started, deadline),
    do: BACstack.who_is_deadline(stack, low, high, started, deadline)

  def who_is_deadline(_, _, _, _, _), do: {:error, Error.new(:invalid_request)}

  @impl Wotex.BACnet.Client
  def subscribe(%{stack: stack}, request, receiver, timeout),
    do: BACstack.subscribe(stack, request, receiver, timeout)

  def subscribe(_, _, _, _), do: {:error, Error.new(:invalid_subscription)}

  @doc false
  @spec subscribe_deadline(term(), term(), term(), term(), term()) :: term()
  def subscribe_deadline(%{stack: stack}, request, receiver, deadline, timeout),
    do: BACstack.subscribe_deadline(stack, request, receiver, deadline, timeout)

  def subscribe_deadline(_, _, _, _, _), do: {:error, Error.new(:invalid_subscription)}

  @impl Wotex.BACnet.Client
  def unsubscribe(%{stack: stack}, subscription, timeout),
    do: BACstack.unsubscribe(stack, subscription, timeout)

  def unsubscribe(_, _, _), do: {:error, Error.new(:invalid_subscription)}

  @impl Wotex.BACnet.Client
  def disconnect(handle) do
    BACstack.disconnect(handle.stack)
    StackOwner.close(handle.owner)
  end

  defp valid_options?(ip, port, timeout) when is_tuple(ip) and tuple_size(ip) == 4 do
    Enum.all?(Tuple.to_list(ip), &(is_integer(&1) and &1 in 0..255)) and
      is_integer(port) and port in 1..65_535 and is_integer(timeout) and timeout in 1..60_000
  end

  defp valid_options?(:none, port, timeout),
    do: is_integer(port) and port in 1..65_535 and is_integer(timeout) and timeout in 1..60_000

  defp valid_options?(_, _, _), do: false

  defp admitted_options?(opts) do
    if Keyword.keyword?(opts) do
      keys = Keyword.keys(opts)

      keys -- [:local_ip, :local_port, :destination, :timeout, :peer_receive, :discovery] == [] and
        length(keys) == MapSet.size(MapSet.new(keys))
    else
      false
    end
  end
end
