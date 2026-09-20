# Validates a locally built candidate directory. This is artifact/source
# evidence only: it does not publish packages, deploy a host or claim hardware.
#
#   mix run --no-start bin/check_distribution.exs --artifacts /absolute/path

Code.require_file("support/distribution.exs", __DIR__)

defmodule Wotex.Lab.Check.LocalDistribution do
  @moduledoc false

  alias Wotex.Lab.Check.Distribution

  @spec run([String.t()]) :: :ok
  def run(["--artifacts", root | options]) when options in [[], ["--require-release"]] do
    (Path.type(root) == :absolute and File.dir?(root)) || abort("artifact root is invalid")
    manifest_path = Path.join(root, "manifest.json")

    with {:ok, bytes} <- File.read(manifest_path),
         {:ok, manifest} <- Wotex.JSON.decode(bytes),
         :ok <- Distribution.validate_manifest(manifest, root),
         paths = MapSet.new(manifest["artifacts"], & &1["path"]),
         :ok <- Distribution.validate_candidate_paths(MapSet.to_list(paths), options != []) do
      inspect_tarballs!(root, paths)
      IO.puts("local distribution: #{MapSet.size(paths)} manifested candidate artifacts are valid")
    else
      _ -> abort("candidate distribution manifest is invalid")
    end
  end

  def run(_) do
    abort(
      "usage: mix run --no-start bin/check_distribution.exs --artifacts ABSOLUTE_PATH [--require-release]"
    )
  end

  defp inspect_tarballs!(root, paths) do
    paths
    |> Enum.filter(&String.ends_with?(&1, [".tar", ".tgz", ".tar.gz"]))
    |> Enum.each(fn relative ->
      path = Path.join(root, relative)

      case :erl_tar.table(String.to_charlist(path), tar_options(relative)) do
        {:ok, entries} -> Enum.each(entries, &safe_entry!/1)
        {:error, reason} -> abort("cannot inspect #{relative}: #{inspect(reason)}")
      end
    end)
  end

  defp tar_options(path) do
    if String.ends_with?(path, [".tgz", ".tar.gz"]), do: [:compressed], else: []
  end

  defp safe_entry!(entry) do
    path = List.to_string(entry)

    (Path.type(path) == :relative and not Enum.member?(Path.split(path), "..")) ||
      abort("candidate archive contains an unsafe path")
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Lab.Check.LocalDistribution.run(System.argv())
