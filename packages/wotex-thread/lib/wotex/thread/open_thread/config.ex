defmodule Wotex.Thread.OpenThread.Config do
  @moduledoc """
  Admits explicit configuration for an owned native OpenThread session.

  Configuration requires an absolute executable path and its lowercase SHA-256,
  an absolute storage path, a supported Spinel radio URL, an interface name, a
  storage mode and a local owner PID.
  Unknown or duplicate options fail. Paths and URLs are limited to 4096 bytes,
  interface names to 15 bytes, and timeout to 1..60,000 milliseconds. Network
  creation is disabled unless explicitly permitted.

  Admission is pure: it checks syntax and field relationships without opening
  files, probing a radio or checking whether an owner is alive. The connection
  and native host perform resource acquisition and ownership checks afterward.
  Inspection omits paths, radio configuration and the owner PID. Callers normally
  supply these options through `Wotex.Thread.OpenThread`.
  """

  alias Wotex.Thread.Error

  @keys [
    :executable,
    :executable_sha256,
    :radio_url,
    :interface,
    :storage_path,
    :storage_mode,
    :owner,
    :timeout,
    :allow_network_creation
  ]
  @enforce_keys [
    :executable,
    :executable_sha256,
    :radio_url,
    :interface,
    :storage_path,
    :storage_mode,
    :owner
  ]
  @derive {Inspect, only: [:interface, :storage_mode, :timeout, :allow_network_creation]}
  defstruct @enforce_keys ++ [timeout: 5000, allow_network_creation: false]

  @type t :: %__MODULE__{
          executable: String.t(),
          executable_sha256: String.t(),
          radio_url: String.t(),
          interface: String.t(),
          storage_path: String.t(),
          storage_mode: :open_existing | :create_new,
          owner: pid(),
          timeout: 1..60_000,
          allow_network_creation: boolean()
        }

  @doc false
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(options) do
    with :ok <- options(options, %{}),
         fields = Map.new(options),
         true <- Enum.all?(@enforce_keys, &Map.has_key?(fields, &1)),
         config = struct!(__MODULE__, fields),
         :ok <- validate(config) do
      {:ok, config}
    else
      _ -> {:error, Error.new(:invalid_options)}
    end
  end

  @doc false
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(%__MODULE__{} = config) when map_size(config) == 10 do
    if Enum.all?(@keys, &Map.has_key?(config, &1)) and paths?(config) and owner?(config) and
         bounds?(config) do
      :ok
    else
      {:error, Error.new(:invalid_options)}
    end
  end

  def validate(_), do: {:error, Error.new(:invalid_options)}

  defp paths?(config),
    do:
      absolute_path?(config.executable) and digest?(config.executable_sha256) and
        absolute_path?(config.storage_path) and radio_url?(config.radio_url) and
        interface?(config.interface)

  defp owner?(config),
    do:
      config.storage_mode in [:open_existing, :create_new] and is_pid(config.owner) and
        node(config.owner) == node()

  defp bounds?(config),
    do:
      is_integer(config.timeout) and config.timeout in 1..60_000 and
        is_boolean(config.allow_network_creation)

  defp options([], _), do: :ok

  defp options([{key, _} | rest], seen) when key in @keys do
    if Map.has_key?(seen, key),
      do: {:error, Error.new(:invalid_options)},
      else: options(rest, Map.put(seen, key, true))
  end

  defp options(_, _), do: {:error, Error.new(:invalid_options)}

  defp absolute_path?("/" <> rest = path) when byte_size(path) <= 4096 do
    rest != "" and String.valid?(path) and not Regex.match?(~r/[\x00-\x1f\x7f]/, path)
  end

  defp absolute_path?(_), do: false

  defp interface?(name) when is_binary(name) and byte_size(name) in 1..15,
    do: Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.-]*\z/, name)

  defp interface?(_), do: false

  defp digest?(value) when is_binary(value),
    do: Regex.match?(~r/\A[0-9a-f]{64}\z/, value)

  defp digest?(_), do: false

  defp radio_url?(url) when is_binary(url) and byte_size(url) in 1..4096 do
    String.valid?(url) and not Regex.match?(~r/[\x00-\x20\x7f]/, url) and
      radio_path?(url) and
      String.starts_with?(url, ["spinel+hdlc+uart:///", "spinel+hdlc+forkpty:///", "spinel+spi:///"])
  end

  defp radio_url?(_), do: false

  defp radio_path?(url) do
    case URI.parse(url) do
      %URI{host: "", path: "/" <> path, fragment: nil, userinfo: nil} -> path != ""
      _ -> false
    end
  end
end
