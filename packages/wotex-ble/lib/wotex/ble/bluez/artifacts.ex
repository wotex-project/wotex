defmodule Wotex.BLE.BlueZ.Artifacts do
  @moduledoc """
  Validates and verifies the two explicit executables of the native BlueZ boundary.

  The SDK host and its independent process guardian each require an absolute
  path and a lowercase SHA-256 digest. `new/1` validates these four selectors
  without accessing the filesystem, environment or clock. It rejects missing,
  duplicate, unknown and forged fields. Inspection exposes only the digests.

  `verify/2` reads both executable regular files under one supplied absolute
  monotonic deadline. It starts no process and retains no open descriptor.
  Verification delegates the 64 MiB file limit and identity checks to
  `Wotex.BLE.BlueZ.Executable`. The deployment files must remain immutable
  between verification and their later path-based execution. An explicitly
  owned startup worker must cover potentially blocked filesystem calls with
  the same deadline and owner-loss cleanup.

  ## Examples

      iex> digest = String.duplicate("a", 64)
      iex> {:ok, artifacts} = Wotex.BLE.BlueZ.Artifacts.new(executable: "/opt/wotex/bluez-native", executable_sha256: digest, guardian: "/opt/wotex/custody", guardian_sha256: digest)
      iex> artifacts.executable
      "/opt/wotex/bluez-native"
  """

  alias Wotex.BLE.BlueZ.Executable
  alias Wotex.BLE.Error

  @fields [:executable, :executable_sha256, :guardian, :guardian_sha256]
  @enforce_keys @fields
  @derive {Inspect, only: [:executable_sha256, :guardian_sha256]}
  defstruct @fields

  @typedoc "Pure native executable selectors, with no filesystem ownership."
  @opaque t :: %__MODULE__{
            executable: String.t(),
            executable_sha256: String.t(),
            guardian: String.t(),
            guardian_sha256: String.t()
          }

  @typedoc "Independently verified SDK and guardian files; neither has been started."
  @type verified :: %{executable: Executable.t(), guardian: Executable.t()}

  @doc "Validates the complete selector set without filesystem I/O."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = selectors) do
    selectors
    |> Map.from_struct()
    |> Map.to_list()
    |> new()
  end

  def new(selectors) do
    with true <- Keyword.keyword?(selectors),
         true <- Enum.sort(Keyword.keys(selectors)) == Enum.sort(@fields),
         values = Map.new(selectors),
         true <- path?(values.executable) and path?(values.guardian),
         true <- digest?(values.executable_sha256) and digest?(values.guardian_sha256) do
      {:ok, struct!(__MODULE__, values)}
    else
      _ -> {:error, Error.new(:invalid_options, :native_artifacts)}
    end
  end

  @doc "Verifies both immutable deployment files within one existing startup deadline."
  @spec verify(term(), term()) :: {:ok, verified()} | {:error, Error.t()}
  def verify(selectors, deadline) do
    with {:ok, selectors} <- new(selectors),
         {:ok, executable} <-
           Executable.verify(selectors.executable, selectors.executable_sha256, deadline),
         {:ok, guardian} <- guardian(selectors, deadline) do
      {:ok, %{executable: executable, guardian: guardian}}
    end
  end

  defp guardian(selectors, deadline) do
    case Executable.verify(selectors.guardian, selectors.guardian_sha256, deadline) do
      {:ok, executable} -> {:ok, executable}
      {:error, error} -> {:error, %{error | field: :guardian}}
    end
  end

  defp path?(value),
    do:
      is_binary(value) and byte_size(value) in 1..4096 and String.valid?(value) and
        Path.type(value) == :absolute and not String.contains?(value, <<0>>)

  defp digest?(value),
    do: is_binary(value) and byte_size(value) == 64 and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
end
