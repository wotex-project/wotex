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

  P03 establishes controller ownership and liveness. Read, write, invoke and
  batch interactions remain unavailable until their later work packages.
  """

  @behaviour Wotex.Matter.Client

  alias Wotex.Matter.Error
  alias Wotex.Matter.Native.{Connection, Handle}

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

  @doc "Submits one validated request; P03 admits only fabric checks."
  @impl Wotex.Matter.Client
  @spec request(Handle.t(), map(), pos_integer()) ::
          {:ok, term()} | {:error, Error.t()}
  def request(%Handle{} = handle, %{fabric_id: fabric_id} = message, timeout)
      when is_integer(timeout) and timeout in 1..60_000 do
    cond do
      fabric_id != handle.fabric_id ->
        {:error, Error.new(:fabric_mismatch)}

      not is_pid(handle.pid) or not valid_generation?(handle.generation) ->
        {:error, Error.new(:invalid_handle)}

      not Map.has_key?(message, :type) or not is_atom(message.type) or
          not Enum.all?(Map.keys(message), &is_atom/1) ->
        {:error, Error.new(:invalid_request)}

      true ->
        Connection.request(handle.pid, handle.generation, message, timeout)
    end
  end

  def request(%Handle{}, _, timeout) when is_integer(timeout) and timeout in 1..60_000,
    do: {:error, Error.new(:invalid_request)}

  def request(_, _, _), do: {:error, Error.new(:invalid_handle)}

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
