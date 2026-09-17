defmodule Wotex.OPCUA.Native.Vendor do
  @moduledoc """
  Verifies vendored native files against their reviewed upstream identities.

  `verify/1` reads the fixed file list from the source manifest compiled into the
  package. Each source and license must be a regular file of exactly its recorded
  byte length and SHA-256 digest. A symlink, missing file or altered byte fails
  before the native build starts a compiler or downloads a dependency. The build
  identity separately records these files and rechecks its complete input set.

  Verification is explicit filesystem work; loading this module performs no
  runtime read. The caller supplies an absolute package-native directory and
  retains ownership of that directory. Verification changes no source file and
  does not establish an SDK service or runtime capability.
  """

  alias Wotex.OPCUA.Native.Workspace

  @manifest Path.expand("../../../../priv/fixtures/native-sources-v1.json", __DIR__)
  @external_resource @manifest
  @files @manifest
         |> File.read!()
         |> Jason.decode!()
         |> Map.fetch!("vendored_sources")
         |> Enum.flat_map(&Map.fetch!(&1, "files"))

  @doc "Checks the fixed vendored source and license identities without modifying their directory."
  @spec verify(term()) :: :ok | {:error, :native_vendor_digest_mismatch}
  def verify(directory) when is_binary(directory) and byte_size(directory) in 1..4096 do
    if String.valid?(directory) and Path.type(directory) == :absolute and
         not String.contains?(directory, <<0>>) and Enum.all?(@files, &matches?(directory, &1)),
       do: :ok,
       else: {:error, :native_vendor_digest_mismatch}
  end

  def verify(_), do: {:error, :native_vendor_digest_mismatch}

  defp matches?(directory, %{"path" => relative, "sha256" => expected, "bytes" => bytes}) do
    path = Path.join(directory, relative)

    with {:ok, %File.Stat{type: :regular, size: ^bytes}} <- File.lstat(path),
         {:ok, ^expected} <- Workspace.digest(path),
         do: true,
         else: (_ -> false)
  end
end
