defmodule Wotex.BACnet.SoftwarePackage do
  @moduledoc false

  alias Wotex.BACnet.SoftwareManifest

  @outer "4961553b41a0a5045d2603026108b5800551a126ab1588d378724e561c54bc1f"
  @inner "8ae88e0d565f880159ec324c7771e49d47685d4304a139f3ce7b9bf5a406c251"
  @url "https://repo.hex.pm/tarballs/bacstack-0.0.1.tar"

  @spec url() :: String.t()
  def url, do: @url

  @spec verify(binary(), term(), String.t()) :: map()
  def verify(archive, lock, installed) do
    verify_lock(lock)

    unless is_binary(archive) and byte_size(archive) <= 1_048_576 and
             SoftwareManifest.hash(archive) == @outer,
           do: fail(:bacstack_archive_mismatch)

    {:ok, entries} = :erl_tar.table({:binary, archive}, [:verbose])
    :ok = SoftwareManifest.archive_members(entries)
    {:ok, files} = :erl_tar.extract({:binary, archive}, [:memory])
    outer = Map.new(files, fn {name, bytes} -> {List.to_string(name), bytes} end)

    unless Enum.sort(Map.keys(outer)) ==
             ["CHECKSUM", "VERSION", "contents.tar.gz", "metadata.config"] and
             outer["VERSION"] == "3" and outer["CHECKSUM"] == String.upcase(@inner) and
             SoftwareManifest.hash(
               outer["VERSION"] <> outer["metadata.config"] <> outer["contents.tar.gz"]
             ) == @inner,
           do: fail(:bacstack_inner_mismatch)

    {:ok, entries} = :erl_tar.table({:binary, outer["contents.tar.gz"]}, [:compressed, :verbose])
    :ok = SoftwareManifest.archive_members(entries)
    {:ok, files} = :erl_tar.extract({:binary, outer["contents.tar.gz"]}, [:compressed, :memory])

    expected =
      Map.new(files, fn {name, bytes} ->
        {List.to_string(name), SoftwareManifest.hash(bytes)}
      end)
      |> Map.put("hex_metadata.config", SoftwareManifest.hash(outer["metadata.config"]))

    actual = verify_installed(installed, expected)

    %{
      "name" => "bacstack",
      "version" => "0.0.1",
      "url" => @url,
      "outer_sha256" => @outer,
      "inner_checksum" => @inner,
      "package_file_count" => length(files),
      "installed_files_sha256" => actual
    }
  end

  @spec verify_lock(term()) :: :ok
  def verify_lock({:hex, :bacstack, "0.0.1", @inner, [:mix], _, "hexpm", @outer}), do: :ok
  def verify_lock(_), do: fail(:bacstack_lock_mismatch)

  @spec verify_installed(String.t(), %{String.t() => String.t()}) :: map()
  def verify_installed(root, expected) do
    unless is_map(expected) and map_size(expected) in 1..4095,
      do: fail(:bacstack_installed_limit)

    allowed =
      [".hex" | Map.keys(expected)]
      |> Enum.flat_map(fn name ->
        parts = Path.split(name)
        Enum.map(1..length(parts), &Path.join(Enum.take(parts, &1)))
      end)
      |> MapSet.new()

    actual = installed_files(root, "", %{}, allowed)
    package = Map.delete(actual, ".hex")

    unless package == expected and Map.has_key?(actual, ".hex"),
      do: fail(:bacstack_installed_mismatch)

    actual
  end

  defp installed_files(root, relative, result, allowed) do
    Enum.reduce(File.ls!(Path.join(root, relative)), result, fn name, files ->
      relative = Path.join(relative, name)
      path = Path.join(root, relative)
      unless MapSet.member?(allowed, relative), do: fail(:bacstack_installed_mismatch)

      case File.lstat(path) do
        {:ok, %{type: :directory}} ->
          installed_files(root, relative, files, allowed)

        {:ok, %{type: :regular, size: size}} when size <= 8_388_608 ->
          unless map_size(files) < 4096, do: fail(:bacstack_installed_limit)
          Map.put(files, relative, SoftwareManifest.digest(path))

        _ ->
          fail(:bacstack_installed_mismatch)
      end
    end)
  end

  defp fail(code), do: Mix.raise(Atom.to_string(code))
end
