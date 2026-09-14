defmodule Wotex.Matter.Native do
  @moduledoc """
  Starts and owns the first-party persistent Matter SDK controller.

  This `Wotex.Matter.Client` implementation executes an absolute
  `wotex-matter-host` path directly through a caller-owned BEAM Port. It checks
  the exact native protocol revision, establishes a fresh flow generation, and
  opens one explicit durable controller identity. No process starts until
  `connect/1` is called, and there is no Python or simulator fallback.

  Creation requires `storage_mode: :create_new` with
  `authority: :generate_root`. Reopening requires
  `storage_mode: :open_existing` with `authority: :stored`. Both modes require
  `lifecycle: :persistent`, an absolute storage path, operational vendor,
  fabric and controller node identifiers, and an absolute PAA trust directory.
  The returned handle is released with `disconnect/1`; the connection also
  closes when its creating process exits.

  P03 establishes controller ownership and liveness. P04 adds finite reads,
  event reads, writes and invokes. P05 adds monitored attribute and event
  subscriptions with native report credit and explicit cancellation.
  """

  @behaviour Wotex.Matter.Client

  alias Wotex.Matter.{Address, Descriptor, Error, Subscription}
  alias Wotex.Matter.Native.{Connection, Handle, Wire}

  @required_options [
    :authority,
    :controller_node_id,
    :executable,
    :fabric_id,
    :lifecycle,
    :paa_trust_store,
    :storage_mode,
    :storage_path,
    :vendor_id
  ]
  @allowed_options [:timeout | @required_options]

  @doc "Starts one persistent native controller owned by the calling process."
  @impl Wotex.Matter.Client
  @spec connect(keyword()) :: {:ok, Handle.t()} | {:error, Error.t()}
  def connect(options) do
    with {:ok, validated} <- validate_options(options),
         {:ok, pid, generation} <- Connection.start(self(), validated) do
      {:ok,
       %Handle{
         pid: pid,
         generation: generation,
         fabric_id: validated.fabric_id
       }}
    end
  end

  @doc "Submits one validated native controller request."
  @impl Wotex.Matter.Client
  @spec request(Handle.t(), map(), pos_integer()) ::
          {:ok, term()} | {:error, Error.t()}
  def request(%Handle{} = handle, %{type: type} = message, timeout)
      when is_atom(type) and is_integer(timeout) and timeout in 1..60_000 do
    cond do
      not is_pid(handle.pid) or not valid_generation?(handle.generation) ->
        {:error, Error.new(:invalid_handle)}

      not Enum.all?(Map.keys(message), &is_atom/1) ->
        {:error, Error.new(:invalid_request)}

      true ->
        case request_fabric(message) do
          {:ok, fabric_id} when fabric_id != handle.fabric_id ->
            {:error, Error.new(:fabric_mismatch)}

          {:ok, _} ->
            case Connection.request(handle.pid, handle.generation, message, timeout) do
              {:ok, result} -> Wire.decode(type, result)
              {:error, _} = error -> error
            end

          _ ->
            {:error, Error.new(:invalid_request)}
        end
    end
  end

  def request(%Handle{}, _, timeout) when is_integer(timeout) and timeout in 1..60_000,
    do: {:error, Error.new(:invalid_request)}

  def request(_, _, _), do: {:error, Error.new(:invalid_handle)}

  @doc "Establishes one native subscription and binds delivery to the receiver process."
  @impl Wotex.Matter.Client
  @spec subscribe(Handle.t(), map(), pid(), pos_integer()) ::
          {:ok, Subscription.t()} | {:error, Error.t()}
  def subscribe(%Handle{} = handle, request, receiver, timeout)
      when is_map(request) and is_pid(receiver) and is_integer(timeout) and
             timeout in 1..60_000 do
    cond do
      not is_pid(handle.pid) or not valid_generation?(handle.generation) ->
        {:error, Error.new(:invalid_handle)}

      not Process.alive?(receiver) ->
        {:error, Error.new(:receiver_closed)}

      true ->
        with {:ok, request} <- validate_subscription_request(request, handle.fabric_id) do
          Connection.subscribe(handle.pid, handle.generation, request, receiver, timeout)
        end
    end
  end

  def subscribe(_, _, _, _), do: {:error, Error.new(:invalid_handle)}

  @doc "Cancels one subscription owned by this native controller."
  @impl Wotex.Matter.Client
  @spec unsubscribe(Handle.t(), Subscription.t(), pos_integer()) ::
          :ok | {:error, Error.t()}
  def unsubscribe(%Handle{} = handle, %Subscription{} = subscription, timeout)
      when is_integer(timeout) and timeout in 1..60_000 do
    if is_pid(handle.pid) and valid_generation?(handle.generation) do
      Connection.unsubscribe(handle.pid, handle.generation, subscription, timeout)
    else
      {:error, Error.new(:invalid_handle)}
    end
  end

  def unsubscribe(_, _, _), do: {:error, Error.new(:invalid_handle)}

  defp request_fabric(%{fabric_id: fabric_id}) when is_integer(fabric_id),
    do: {:ok, fabric_id}

  defp request_fabric(%{type: type, paths: paths})
       when type in [:read_paths, :read_events] and is_list(paths) and paths != [] do
    fabrics = Enum.map(paths, fn path -> if is_map(path), do: Map.get(path, :fabric_id) end)

    case Enum.uniq(fabrics) do
      [fabric_id] when is_integer(fabric_id) -> {:ok, fabric_id}
      _ -> :error
    end
  end

  defp request_fabric(_), do: :error

  defp validate_subscription_request(request, fabric_id) do
    keys = [:kind, :paths, :min_interval_s, :max_interval_s, :resubscribe, :queue_limit]

    with true <- Enum.sort(Map.keys(request)) == Enum.sort(keys),
         kind when kind in [:attribute, :event] <- request.kind,
         true <- is_list(request.paths) and length(request.paths) in 1..64,
         true <- is_integer(request.min_interval_s) and request.min_interval_s in 0..65_535,
         true <- is_integer(request.max_interval_s) and request.max_interval_s in 1..65_535,
         true <- request.min_interval_s <= request.max_interval_s,
         true <- is_boolean(request.resubscribe),
         true <- is_integer(request.queue_limit) and request.queue_limit in 1..10_000,
         {:ok, paths} <- validate_subscription_paths(request.paths, kind, fabric_id),
         true <- length(paths) == length(Enum.uniq(paths)) do
      {:ok, %{request | paths: paths}}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_subscription)}
    end
  end

  defp validate_subscription_paths(paths, kind, fabric_id) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, acc} ->
      with {:ok, address} <- Address.new(path),
           true <- address.fabric_id == fabric_id,
           {:ok, _} <- Descriptor.lookup(kind, address, :subscribe) do
        {:cont, {:ok, [Map.from_struct(address) | acc]}}
      else
        false -> {:halt, {:error, Error.new(:fabric_mismatch)}}
        {:error, %Error{}} = error -> {:halt, error}
        _ -> {:halt, {:error, Error.new(:invalid_subscription)}}
      end
    end)
    |> case do
      {:ok, paths} -> {:ok, Enum.reverse(paths)}
      error -> error
    end
  end

  @doc "Performs a real local protocol probe against the owned native controller."
  @spec health(Handle.t(), pos_integer()) :: {:ok, map()} | {:error, Error.t()}
  def health(handle, timeout \\ 1_000)

  def health(%Handle{} = handle, timeout)
      when is_integer(timeout) and timeout in 1..60_000 do
    if is_pid(handle.pid) and valid_generation?(handle.generation) do
      Connection.health(handle.pid, handle.generation, timeout)
    else
      {:error, Error.new(:invalid_handle)}
    end
  end

  def health(_, _), do: {:error, Error.new(:invalid_handle)}

  @doc "Closes the owned native controller; already closed handles are harmless."
  @impl Wotex.Matter.Client
  @spec disconnect(Handle.t()) :: :ok | {:error, Error.t()}
  def disconnect(%Handle{pid: pid, generation: generation})
      when is_pid(pid) and is_binary(generation) do
    Connection.disconnect(pid, generation)
  end

  def disconnect(_), do: :ok

  defp validate_options(options) when is_list(options) do
    keys = if Keyword.keyword?(options), do: Keyword.keys(options), else: []

    if keys != [] and length(keys) == length(Enum.uniq(keys)) and
         Enum.sort(keys -- [:timeout]) == Enum.sort(@required_options) and
         keys -- @allowed_options == [] do
      validate_values(Map.new(options))
    else
      {:error, Error.new(:invalid_options)}
    end
  end

  defp validate_options(_), do: {:error, Error.new(:invalid_options)}

  defp validate_values(options) do
    timeout = Map.get(options, :timeout, 5_000)
    mode = {options.storage_mode, options.authority}

    with true <- options.lifecycle == :persistent,
         true <- mode in [{:create_new, :generate_root}, {:open_existing, :stored}],
         true <- integer?(options.vendor_id, 1, 65_534),
         true <- integer?(options.fabric_id, 1, 0xFFFFFFFFFFFFFFFF),
         true <- integer?(options.controller_node_id, 1, 0xFFFFFFEFFFFFFFFF),
         true <- integer?(timeout, 1, 60_000),
         :ok <- absolute_path(options.storage_path),
         :ok <- absolute_path(options.paa_trust_store),
         :ok <- executable(options.executable),
         :ok <- trust_directory(options.paa_trust_store) do
      {:ok,
       options
       |> Map.put(:timeout, timeout)
       |> Map.update!(:lifecycle, &Atom.to_string/1)
       |> Map.update!(:storage_mode, &Atom.to_string/1)
       |> Map.update!(:authority, &Atom.to_string/1)}
    else
      _ -> {:error, Error.new(:invalid_options)}
    end
  end

  defp executable(path) do
    with :ok <- absolute_path(path),
         {:ok, %{type: :regular, mode: mode}} <- File.lstat(path),
         true <- Bitwise.band(mode, 0o111) != 0 do
      :ok
    else
      _ -> :error
    end
  end

  defp trust_directory(path) do
    case File.lstat(path) do
      {:ok, %{type: :directory}} -> :ok
      _ -> :error
    end
  end

  defp absolute_path(path) when is_binary(path) do
    if Path.type(path) == :absolute and byte_size(path) <= 4_096 and
         not String.contains?(path, <<0>>),
       do: :ok,
       else: :error
  end

  defp absolute_path(_), do: :error

  defp integer?(value, minimum, maximum),
    do: is_integer(value) and value >= minimum and value <= maximum

  defp valid_generation?(generation),
    do: is_binary(generation) and Regex.match?(~r/\A[0-9a-f]{32}\z/, generation)
end
