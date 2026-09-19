defmodule Wotex.BLE.Software.Fixture do
  @moduledoc """
  Describes the explicit BlueZ virtual-controller software fixture inputs.

  The fixture is available only from a repository checkout, where `wotex-ble`
  and its sibling packages `wotex` and `wotex-runtime` sit side by side under
  `packages/`. `inputs/1` hashes every regular file in `test/interop/virtual`
  and the `mix.exs`, `mix.lock`, `config`, `lib`, `priv` and `test` trees of the
  three packages, recording each mode. Links and special
  files fail. Build directories, dependencies, Python caches and PLTs are not
  inputs. The identity binds source content; it does not attest that any fixture
  image was built or executed.
  """

  alias Wotex.BLE.Native.Source

  @packages ~w(wotex wotex-runtime wotex-ble)
  @directories ~w(config lib priv test)
  @ignored ~w(_build deps plts)
  @maximum_files 20_000

  @typedoc "Relative source path to content digest and permission bits."
  @type inputs :: %{String.t() => %{String.t() => String.t() | non_neg_integer()}}

  @doc "Returns the package names copied into the guest image."
  @spec packages() :: [String.t()]
  def packages, do: @packages

  @doc "Hashes the fixture assets and the sources of an explicit package root and its siblings."
  @spec inputs(term()) :: {:ok, inputs()} | {:error, :invalid_software_sources}
  def inputs(root) when is_binary(root) do
    with true <- Path.type(root) == :absolute,
         {:ok, assets} <- assets(root),
         {:ok, sources} <- sources(Path.dirname(root)) do
      {:ok, Map.merge(assets, sources)}
    else
      _ -> {:error, :invalid_software_sources}
    end
  end

  def inputs(_), do: {:error, :invalid_software_sources}

  @doc "Counts the literal ExUnit test definitions in the public and stress software lane files."
  @spec public_case_count(String.t()) :: {:ok, pos_integer()} | {:error, :invalid_software_sources}
  def public_case_count(root) do
    counts =
      for file <-
            ~w(test/interop/bluez_test.exs test/interop/bluez_runtime_test.exs test/software/lifecycle_stress_test.exs) do
        case File.read(Path.join(root, file)) do
          {:ok, bytes} -> length(Regex.scan(~r/^\s*test "/m, bytes))
          _ -> 0
        end
      end

    if Enum.all?(counts, &(&1 > 0)),
      do: {:ok, Enum.sum(counts)},
      else: {:error, :invalid_software_sources}
  end

  defp assets(root) do
    directory = Path.join(root, "test/interop/virtual")

    with {:ok, names} <- File.ls(directory) do
      names
      |> Enum.sort()
      |> Enum.reduce_while({:ok, %{}}, fn name, {:ok, found} ->
        relative = "wotex-ble/test/interop/virtual/" <> name

        case entry(Path.join(directory, name)) do
          {:ok, value} -> {:cont, {:ok, Map.put(found, relative, value)}}
          _ -> {:halt, :error}
        end
      end)
    end
  end

  defp sources(parent) do
    Enum.reduce_while(@packages, {:ok, %{}}, fn package, {:ok, found} ->
      root = Path.join(parent, package)

      with {:ok, files} <- package_files(root),
           {:ok, entries} <- entries(root, package, files) do
        {:cont, {:ok, Map.merge(found, entries)}}
      else
        _ -> {:halt, :error}
      end
    end)
  end

  defp package_files(root) do
    with {:ok, %File.Stat{type: :regular}} <- File.lstat(Path.join(root, "mix.exs")),
         {:ok, %File.Stat{type: :regular}} <- File.lstat(Path.join(root, "mix.lock")) do
      Enum.reduce_while(@directories, {:ok, ["mix.exs", "mix.lock"]}, fn directory, {:ok, files} ->
        case walk(root, directory) do
          {:ok, found} -> {:cont, {:ok, files ++ found}}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp walk(root, relative) do
    case File.lstat(Path.join(root, relative)) do
      {:error, :enoent} -> {:ok, []}
      {:ok, %File.Stat{type: :directory}} -> walk_directory(root, relative)
      {:ok, %File.Stat{type: :regular}} -> {:ok, [relative]}
      _ -> :error
    end
  end

  defp walk_directory(root, relative) do
    if Path.basename(relative) in @ignored do
      {:ok, []}
    else
      with {:ok, names} <- File.ls(Path.join(root, relative)) do
        Enum.reduce_while(Enum.sort(names), {:ok, []}, &walk_child(root, relative, &1, &2))
      end
    end
  end

  defp walk_child(root, relative, name, {:ok, files}) do
    case walk(root, Path.join(relative, name)) do
      {:ok, found} when length(files) + length(found) <= @maximum_files ->
        {:cont, {:ok, files ++ found}}

      _ ->
        {:halt, :error}
    end
  end

  defp entries(root, package, files) do
    Enum.reduce_while(files, {:ok, %{}}, fn relative, {:ok, found} ->
      case entry(Path.join(root, relative)) do
        {:ok, value} -> {:cont, {:ok, Map.put(found, package <> "/" <> relative, value)}}
        _ -> {:halt, :error}
      end
    end)
  end

  defp entry(path) do
    with {:ok, %File.Stat{type: :regular, mode: mode}} <- File.lstat(path),
         {:ok, digest} <- Source.digest(path) do
      {:ok, %{"sha256" => digest, "mode" => Bitwise.band(mode, 0o777)}}
    else
      _ -> :error
    end
  end
end
