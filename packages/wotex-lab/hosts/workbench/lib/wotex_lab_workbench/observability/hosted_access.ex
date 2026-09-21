defmodule WotexLabWorkbench.Observability.HostedAccess do
  @moduledoc """
  Fail-closed tenant admission for the hosted metric and investigation surface.

  The checked configuration contains only SHA-256 credential digests. A
  successful request receives a short owner-bound lease and a server-owned
  metric instance; neither value can be selected by the request body. Query and
  investigation concurrency and rate windows are fixed here so a listener or
  worker cannot loosen them accidentally.
  """

  use GenServer

  alias Wotex.Lab.{Error, Options}
  alias WotexLabWorkbench.Observability.DurableReader

  @schema "wotex-lab-hosted-tenants/v1"
  @max_file_bytes 65_536
  @max_tenants 64
  @max_leases 64
  @token ~r/\A[A-Za-z0-9_-]{43,128}\z/
  @digest ~r/\Asha256:[0-9a-f]{64}\z/
  @identifier ~r/\A[a-z0-9](?:[a-z0-9_.-]{0,62}[a-z0-9])?\z/
  @purposes %{
    query: %{window_ms: 60_000, calls: 60, active: 2},
    investigation: %{window_ms: 3_600_000, calls: 4, active: 1}
  }

  @type tenant :: %{
          id: String.t(),
          instance: String.t(),
          token_digest: <<_::256>>
        }

  @doc "Loads and validates a bounded digest-only tenant file."
  @spec load(Path.t(), [term()]) :: {:ok, [tenant()]} | {:error, Error.t()}
  def load(path, reserved_tokens \\ []) do
    with true <- is_binary(path) and Path.type(path) == :absolute,
         {:ok, before} <- File.lstat(path),
         true <- before.type == :regular and before.size in 1..@max_file_bytes,
         true <- Bitwise.band(before.mode, 0o077) == 0,
         {:ok, bytes} <- File.read(path),
         true <- byte_size(bytes) == before.size,
         {:ok, after_stat} <- File.lstat(path),
         true <- stable?(before, after_stat),
         {:ok, document} <- Jason.decode(bytes),
         {:ok, tenants} <- admit(document, reserved_tokens) do
      {:ok, tenants}
    else
      _ -> invalid(:invalid_hosted_tenants, "hosted tenant configuration is invalid")
    end
  end

  @doc "Validates a decoded tenant document without retaining supplied credentials."
  @spec admit(term(), [term()]) :: {:ok, [tenant()]} | {:error, Error.t()}
  def admit(%{"schema_version" => @schema, "tenants" => entries} = document, reserved_tokens)
      when map_size(document) == 2 and is_list(entries) and
             length(entries) in 1..@max_tenants and is_list(reserved_tokens) do
    with {:ok, tenants} <- parse_tenants(entries),
         true <- unique?(tenants, :id),
         true <- unique?(tenants, :instance),
         true <- unique?(tenants, :token_digest),
         true <- distinct_from_reserved?(tenants, reserved_tokens) do
      {:ok, tenants}
    else
      _ -> invalid(:invalid_hosted_tenants, "hosted tenant configuration is invalid")
    end
  end

  def admit(_, _),
    do: invalid(:invalid_hosted_tenants, "hosted tenant configuration is invalid")

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start() | {:error, Error.t()}
  def start_link(opts) do
    with :ok <- Options.validate(opts, [:tenants, :durable]),
         tenants when is_list(tenants) <- Keyword.get(opts, :tenants),
         true <- tenants != [] and length(tenants) <= @max_tenants,
         true <- Enum.all?(tenants, &valid_tenant?/1),
         true <- unique?(tenants, :id),
         true <- unique?(tenants, :instance),
         true <- unique?(tenants, :token_digest),
         durable when is_list(durable) <- Keyword.get(opts, :durable),
         :ok <- DurableReader.validate(durable) do
      GenServer.start_link(
        __MODULE__,
        %{tenants: tenants, durable: DurableReader.executor(durable)},
        name: __MODULE__
      )
    else
      {:error, _} = error -> error
      _ -> invalid(:invalid_hosted_access, "hosted tenant access is invalid")
    end
  end

  @doc "Authenticates one token and opens an owner-bound, rate-limited lease."
  @spec open(String.t(), :query | :investigation) ::
          {:ok, map()} | {:error, Error.t()}
  def open(token, purpose) when purpose in [:query, :investigation] do
    if token?(token) do
      GenServer.call(__MODULE__, {:open, :crypto.hash(:sha256, token), purpose})
    else
      denied()
    end
  catch
    :exit, _ -> unavailable()
  end

  def open(_, _), do: denied()

  @doc "Releases a lease owned by the calling process."
  @spec release(reference()) :: :ok
  def release(reference) when is_reference(reference) do
    GenServer.call(__MODULE__, {:release, reference})
  catch
    :exit, _ -> :ok
  end

  def release(_), do: :ok

  @doc "Returns bounded counters without tenant identifiers or credential material."
  @spec stats() :: map() | {:error, Error.t()}
  def stats do
    GenServer.call(__MODULE__, :stats)
  catch
    :exit, _ -> unavailable()
  end

  @impl GenServer
  def init(config),
    do: {:ok, Map.merge(config, %{leases: %{}, monitors: %{}, usage: %{}})}

  @impl GenServer
  def handle_call({:open, digest, purpose}, {owner, _}, state) do
    now = System.monotonic_time(:millisecond)
    state = refresh_windows(state, now)

    with {:ok, tenant} <- authenticate(state.tenants, digest),
         :ok <- capacity(state, tenant.id, purpose),
         {state, usage} <- charge(state, tenant.id, purpose, now) do
      reference = make_ref()
      monitor = Process.monitor(owner)

      lease = %{
        owner: owner,
        monitor: monitor,
        tenant_id: tenant.id,
        instance: tenant.instance,
        purpose: purpose
      }

      state =
        state
        |> put_in([:leases, reference], lease)
        |> put_in([:monitors, monitor], reference)
        |> put_in([:usage, {tenant.id, purpose}], usage)

      reply = %{
        lease: reference,
        instance: tenant.instance,
        durable: state.durable
      }

      {:reply, {:ok, reply}, state}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:release, reference}, {owner, _}, state) do
    state =
      case state.leases[reference] do
        %{owner: ^owner} -> drop_lease(state, reference)
        _ -> state
      end

    {:reply, :ok, state}
  end

  def handle_call(:stats, _, state) do
    counts = Enum.frequencies_by(state.leases, fn {_, lease} -> lease.purpose end)

    {:reply,
     %{
       tenants: length(state.tenants),
       active_queries: Map.get(counts, :query, 0),
       active_investigations: Map.get(counts, :investigation, 0),
       max_leases: @max_leases
     }, state}
  end

  @impl GenServer
  def handle_info({:DOWN, monitor, :process, _, _}, state) do
    case state.monitors[monitor] do
      nil -> {:noreply, state}
      reference -> {:noreply, drop_lease(state, reference)}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  defp parse_tenants(entries) do
    result =
      Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
        case tenant(entry) do
          {:ok, tenant} -> {:cont, {:ok, [tenant | acc]}}
          :error -> {:halt, :error}
        end
      end)

    case result do
      {:ok, tenants} -> {:ok, Enum.sort_by(tenants, & &1.id)}
      :error -> :error
    end
  end

  defp tenant(
         %{
           "id" => id,
           "instance" => instance,
           "token_sha256" => "sha256:" <> encoded
         } = entry
       )
       when map_size(entry) == 3 do
    with true <- identifier?(id) and identifier?(instance),
         true <- Regex.match?(@digest, "sha256:" <> encoded),
         {:ok, digest} <- Base.decode16(encoded, case: :lower),
         true <- byte_size(digest) == 32 do
      {:ok, %{id: id, instance: instance, token_digest: digest}}
    else
      _ -> :error
    end
  end

  defp tenant(_), do: :error

  defp valid_tenant?(%{id: id, instance: instance, token_digest: digest} = tenant)
       when map_size(tenant) == 3,
       do:
         identifier?(id) and identifier?(instance) and is_binary(digest) and byte_size(digest) == 32

  defp valid_tenant?(_), do: false

  defp authenticate(tenants, digest) when is_binary(digest) and byte_size(digest) == 32 do
    matches =
      Enum.filter(tenants, fn tenant ->
        Plug.Crypto.secure_compare(tenant.token_digest, digest)
      end)

    case matches do
      [tenant] -> {:ok, tenant}
      _ -> denied()
    end
  end

  defp capacity(state, tenant_id, purpose) do
    policy = @purposes[purpose]
    usage = Map.get(state.usage, {tenant_id, purpose}, empty_usage(0))

    cond do
      map_size(state.leases) >= @max_leases -> busy(:hosted_capacity)
      usage.active >= policy.active -> busy(:tenant_concurrency)
      usage.calls >= policy.calls -> busy(:tenant_rate_limited)
      true -> :ok
    end
  end

  defp charge(state, tenant_id, purpose, now) do
    key = {tenant_id, purpose}
    usage = Map.get(state.usage, key, empty_usage(now))
    {state, %{usage | calls: usage.calls + 1, active: usage.active + 1}}
  end

  defp drop_lease(state, reference) do
    case Map.pop(state.leases, reference) do
      {nil, _} ->
        state

      {lease, leases} ->
        Process.demonitor(lease.monitor, [:flush])
        key = {lease.tenant_id, lease.purpose}
        usage = Map.get(state.usage, key, empty_usage(System.monotonic_time(:millisecond)))
        usage = %{usage | active: max(usage.active - 1, 0)}

        %{
          state
          | leases: leases,
            monitors: Map.delete(state.monitors, lease.monitor),
            usage: Map.put(state.usage, key, usage)
        }
    end
  end

  defp refresh_windows(state, now) do
    usage =
      Map.new(state.usage, fn {{_, purpose} = key, value} ->
        if now - value.started_at >= @purposes[purpose].window_ms,
          do: {key, %{value | started_at: now, calls: 0}},
          else: {key, value}
      end)

    %{state | usage: usage}
  end

  defp empty_usage(now), do: %{started_at: now, calls: 0, active: 0}

  defp distinct_from_reserved?(tenants, tokens) do
    reserved =
      tokens
      |> Enum.filter(&token?/1)
      |> Enum.map(&:crypto.hash(:sha256, &1))

    Enum.all?(tenants, fn tenant ->
      Enum.all?(reserved, &(not Plug.Crypto.secure_compare(tenant.token_digest, &1)))
    end)
  end

  defp unique?(values, key),
    do: length(values) == length(Enum.uniq_by(values, &Map.fetch!(&1, key)))

  defp identifier?(value),
    do: is_binary(value) and byte_size(value) in 1..64 and Regex.match?(@identifier, value)

  defp token?(value),
    do: is_binary(value) and byte_size(value) in 43..128 and Regex.match?(@token, value)

  defp stable?(left, right),
    do:
      left.type == right.type and left.size == right.size and left.inode == right.inode and
        left.major_device == right.major_device and left.minor_device == right.minor_device and
        left.mode == right.mode and left.mtime == right.mtime and left.ctime == right.ctime

  defp denied,
    do: invalid(:hosted_unauthorized, "hosted tenant credential is not admitted")

  defp unavailable,
    do: invalid(:hosted_unavailable, "hosted tenant access is unavailable")

  defp busy(code), do: invalid(code, "hosted tenant capacity is exhausted")

  defp invalid(code, message), do: {:error, Error.new(code, :hosted_access, message)}
end
