defmodule Wotex.Lab.Check.ReleaseReview do
  @moduledoc false

  @direct ~w(wotex_lab wotex wotex_nx wotex_runtime wotex_directory wotex_continuum
             wotex_binding_http wotex_binding_mqtt ex_maude nx explorer telemetry
             telemetry_metrics prom_ex beamlens phoenix phoenix_html phoenix_live_view
             phoenix_pubsub bandit jason req)

  @spec bom!(Path.t(), [map()], [map()]) :: map()
  def bom!(consumer, resolved, admitted) do
    lock = Wotex.Lab.Check.ArchiveRepository.read_lock!(Path.join(consumer, "mix.lock"))
    active = MapSet.new(resolved, & &1.name)
    archives = Map.new(admitted, &{{&1.name, &1.version}, &1})
    refs = Map.new(resolved, &{&1.name, reference(&1.name, &1.version)})

    Enum.each(@direct, fn name ->
      MapSet.member?(active, name) || abort("release review omitted direct dependency #{name}")
    end)

    components =
      resolved
      |> Enum.sort_by(&{&1.name, &1.version})
      |> Enum.map(fn item ->
        archive = Map.fetch!(archives, {item.name, item.version})

        component = %{
          "type" => "library",
          "bom-ref" => Map.fetch!(refs, item.name),
          "name" => item.name,
          "version" => item.version,
          "purl" => "pkg:hex/#{item.name}@#{item.version}",
          "licenses" => Enum.map(licenses!(archive.path), &%{"license" => %{"name" => &1}}),
          "properties" => [
            %{
              "name" => "wotex:archive-origin",
              "value" => Atom.to_string(archive.origin)
            }
          ]
        }

        case hashes(archive, item.archive) do
          [] -> component
          values -> Map.put(component, "hashes", values)
        end
      end)

    dependencies =
      [%{"ref" => "pkg:hex/wotex_lab_workbench@0.1.0", "dependsOn" => direct_refs(refs)}] ++
        Enum.map(resolved, fn item ->
          %{
            "ref" => Map.fetch!(refs, item.name),
            "dependsOn" => dependency_refs(lock, item.name, active, refs)
          }
        end)

    bom = %{
      "$schema" => "https://cyclonedx.org/schema/bom-1.7.schema.json",
      "bomFormat" => "CycloneDX",
      "specVersion" => "1.7",
      "version" => 1,
      "metadata" => %{
        "component" => %{
          "type" => "application",
          "bom-ref" => "pkg:hex/wotex_lab_workbench@0.1.0",
          "name" => "wotex_lab_workbench",
          "version" => "0.1.0"
        },
        "properties" => [
          %{"name" => "wotex:dependency-mode", "value" => "local-candidate-archives"},
          %{"name" => "wotex:production-closure", "value" => "true"}
        ]
      },
      "components" => components,
      "dependencies" => Enum.sort_by(dependencies, & &1["ref"])
    }

    validate!(bom)
    bom
  end

  @spec encode!(map()) :: String.t()
  def encode!(bom), do: JSON.encode!(bom) <> "\n"

  defp validate!(bom) do
    component_refs = Enum.map(bom["components"], & &1["bom-ref"])
    root_ref = bom["metadata"]["component"]["bom-ref"]
    known = MapSet.new([root_ref | component_refs])
    dependency_refs = Enum.map(bom["dependencies"], & &1["ref"])

    cond do
      length(component_refs) != length(Enum.uniq(component_refs)) ->
        abort("CycloneDX SBOM has duplicate component references")

      MapSet.new(dependency_refs) != known ->
        abort("CycloneDX SBOM dependency subjects do not match its components")

      Enum.any?(bom["dependencies"], fn relation ->
        Enum.any?(relation["dependsOn"], &(not MapSet.member?(known, &1)))
      end) ->
        abort("CycloneDX SBOM contains an unresolved dependency reference")

      Enum.any?(bom["components"], &(&1["licenses"] == [])) ->
        abort("CycloneDX SBOM contains an unlicensed component")

      true ->
        :ok
    end
  end

  defp dependency_refs(lock, name, active, refs) do
    entry = Enum.find_value(lock, fn {app, value} -> if Atom.to_string(app) == name, do: value end)

    case entry do
      {:hex, _, _, _, _, dependencies, "hexpm", _} ->
        dependencies
        |> Enum.map(fn {app, _, _} -> Atom.to_string(app) end)
        |> Enum.filter(&MapSet.member?(active, &1))
        |> Enum.map(&Map.fetch!(refs, &1))
        |> Enum.uniq()
        |> Enum.sort()

      _ ->
        []
    end
  end

  defp direct_refs(refs) do
    @direct
    |> Enum.map(&Map.fetch!(refs, &1))
    |> Enum.sort()
  end

  defp hashes(%{origin: :built}, _), do: []

  defp hashes(%{origin: :hex_cache}, "sha256:" <> digest),
    do: [%{"alg" => "SHA-256", "content" => digest}]

  defp licenses!(archive) do
    metadata =
      case :erl_tar.extract(String.to_charlist(archive), [:memory, files: [~c"metadata.config"]]) do
        {:ok, [{~c"metadata.config", bytes}]} ->
          bytes

        other ->
          abort("cannot read archive metadata from #{Path.basename(archive)}: #{inspect(other)}")
      end

    temporary =
      Path.join(
        System.tmp_dir!(),
        "wotex-hex-metadata-" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
      )

    try do
      File.write!(temporary, metadata, [:exclusive])

      terms =
        case :file.consult(String.to_charlist(temporary)) do
          {:ok, terms} -> terms
          {:error, reason} -> abort("invalid Hex archive metadata: #{inspect(reason)}")
        end

      case Enum.find_value(terms, fn
             {"licenses", values} -> values
             _ -> nil
           end) do
        values when is_list(values) and values != [] ->
          Enum.map(values, fn value ->
            license = to_string(value)

            if license == "" or byte_size(license) > 128,
              do: abort("archive contains an invalid license value")

            license
          end)

        _ ->
          abort("archive #{Path.basename(archive)} has no declared license")
      end
    after
      File.rm(temporary)
    end
  end

  defp reference(name, version), do: "pkg:hex/#{name}@#{version}"

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end
