defmodule Wotex.CoAP.NativeBackend do
  @moduledoc """
  Verifies an explicitly selected native OSCORE executable and build manifest.

  `verify/1` accepts only the WCO-N02 `:native_backend` map. Both paths must
  identify ordinary files rather than symbolic links. The executable retains
  its existing permission bits and must already be executable. The manifest is
  bounded before reading, decoded with Wotex JSON limits, and bound to libcoap
  4.3.5 at the specified source revision. Its lowercase SHA-256 identity must
  match the selected executable.

  Verification starts no Port, changes no permission, searches no executable
  path and reads no application environment. Consumers supply build and
  lifecycle policy; the native session owner performs this check before it
  creates the selected process.
  """

  alias Wotex.CoAP.Error

  @backend "libcoap"
  @executable_name "wotex-coap-oscore"
  @manifest_schema "wotex.coap.native@1"
  @revision "7cf7465b784baded4de183290c547d582becfd28"
  @version "4.3.5"
  @maximum_manifest_bytes 1_048_576
  @maximum_path_bytes 4_096
  @json_limits [
    max_bytes: @maximum_manifest_bytes,
    max_depth: 8,
    max_nodes: 4_096,
    max_collection_size: 1_024,
    max_string_bytes: 131_072
  ]

  @enforce_keys [:executable, :manifest, :sha256]
  defstruct [:executable, :manifest, :sha256]

  @opaque t :: %__MODULE__{
            executable: String.t(),
            manifest: String.t(),
            sha256: String.t()
          }

  @doc "Verifies the exact native backend selection without starting its executable."
  @spec verify(term()) :: {:ok, t()} | {:error, Error.t()}
  def verify(%{executable: executable, manifest: manifest} = input) when map_size(input) == 2 do
    with :ok <- path(executable),
         :ok <- path(manifest),
         {:ok, executable_stat} <- ordinary(executable),
         true <- executable?(executable_stat.mode),
         {:ok, manifest_stat} <- ordinary(manifest),
         true <- manifest_stat.size <= @maximum_manifest_bytes,
         {:ok, manifest_bytes} <- File.read(manifest),
         true <- byte_size(manifest_bytes) <= @maximum_manifest_bytes,
         {:ok, decoded} <- Wotex.JSON.decode(manifest_bytes, @json_limits),
         {:ok, expected_hash} <- manifest_hash(decoded),
         ^expected_hash <- digest(executable) do
      {:ok, %__MODULE__{executable: executable, manifest: manifest, sha256: expected_hash}}
    else
      _ -> failure()
    end
  rescue
    _ in [ArgumentError, File.Error] -> failure()
  end

  def verify(_), do: failure()

  defp manifest_hash(%{
         "schema" => @manifest_schema,
         "backend" => %{
           "name" => @backend,
           "version" => @version,
           "revision" => @revision
         },
         "executables" => %{
           @executable_name => %{"sha256" => hash}
         }
       })
       when is_binary(hash) do
    if Regex.match?(~r/\A[0-9a-f]{64}\z/, hash), do: {:ok, hash}, else: :error
  end

  defp manifest_hash(_), do: :error

  defp ordinary(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular} = stat} -> {:ok, stat}
      _ -> :error
    end
  end

  defp path(value) when is_binary(value) and byte_size(value) in 1..@maximum_path_bytes do
    if String.valid?(value) and :binary.match(value, <<0>>) == :nomatch and
         Path.type(value) == :absolute,
       do: :ok,
       else: :error
  end

  defp path(_), do: :error
  defp executable?(mode), do: Bitwise.band(mode, 0o111) != 0

  defp digest(path) do
    path
    |> File.stream!(65_536, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp failure, do: {:error, Error.new(:unsupported_native_backend, :native_backend)}
end
