defmodule Wotex.Workspace.NativeArtifact.Verifier do
  @moduledoc """
  Read-only verification of one native artifact archive.

  Verification scans the archive under explicit limits, validates its payload
  manifest, checks descriptor and target admission, and compares every payload
  entry. It never extracts, adopts, downloads or publishes bytes.
  """

  alias Wotex.Workspace.NativeArtifact.Archive
  alias Wotex.Workspace.NativeArtifact.Descriptor
  alias Wotex.Workspace.NativeArtifact.PayloadManifest

  defmodule Result do
    @moduledoc "A completely verified local artifact, not an adopted artifact."

    @enforce_keys [:manifest, :transport_sha256, :compressed_size, :expanded_size]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            manifest: PayloadManifest.t(),
            transport_sha256: String.t(),
            compressed_size: non_neg_integer(),
            expanded_size: non_neg_integer()
          }
  end

  @doc "Verifies one local archive against an admitted descriptor and build identity."
  @spec verify(Path.t(), Descriptor.t(), String.t(), String.t(), Archive.Limits.t()) ::
          {:ok, Result.t()} | {:error, [String.t()]}
  def verify(
        archive,
        %Descriptor{} = descriptor,
        target,
        expected_build_identity,
        %Archive.Limits{} = limits \\ %Archive.Limits{}
      ) do
    with {:ok, scan} <- wrap(Archive.scan(archive, limits)),
         {:ok, manifest} <-
           wrap(
             PayloadManifest.decode(scan.manifest_bytes,
               max_bytes: limits.manifest_bytes,
               max_depth: 32,
               max_nodes: limits.entries * 16 + 128
             )
           ),
         :ok <- validate(manifest, scan.entries, descriptor, target, expected_build_identity) do
      {:ok,
       %Result{
         manifest: manifest,
         transport_sha256: scan.transport_sha256,
         compressed_size: scan.compressed_size,
         expanded_size: scan.expanded_size
       }}
    end
  end

  defp validate(manifest, actual_entries, descriptor, target, expected_build_identity) do
    errors =
      []
      |> mismatch("package", descriptor.package, manifest.package)
      |> mismatch("profile", descriptor.profile, manifest.profile)
      |> mismatch("target", target, manifest.target)
      |> mismatch("build identity", expected_build_identity, manifest.build_identity)
      |> target_errors(descriptor, target)
      |> descriptor_errors(manifest.entries, descriptor.raw["outputs"])
      |> entry_errors(manifest.entries, actual_entries)

    if errors == [], do: :ok, else: {:error, Enum.reverse(errors)}
  end

  defp target_errors(errors, descriptor, target) do
    case Descriptor.target(descriptor, target) do
      {:ok, %{status: :supported}} ->
        errors

      {:ok, %{status: :unsupported, reason: reason}} ->
        ["target is unsupported: #{reason}" | errors]

      {:error, reason} ->
        [reason | errors]
    end
  end

  defp descriptor_errors(errors, entries, outputs) do
    by_path = Map.new(entries, &{&1["path"], &1})

    errors =
      Enum.reduce(outputs, errors, fn output, acc ->
        case Map.get(by_path, output["path"]) do
          nil ->
            if output["required"],
              do: ["missing declared output #{output["path"]}" | acc],
              else: acc

          entry ->
            acc
            |> mismatch("#{output["path"]} kind", output["kind"], entry["kind"])
            |> mismatch("#{output["path"]} mode", output["mode"], entry["mode"])
        end
      end)

    Enum.reduce(entries, errors, fn entry, acc ->
      if admitted_entry?(entry["path"], outputs) do
        acc
      else
        ["undeclared output #{entry["path"]}" | acc]
      end
    end)
  end

  defp admitted_entry?(path, outputs) do
    Enum.any?(outputs, fn output ->
      path == output["path"] or
        (output["kind"] == "directory" and String.starts_with?(path, output["path"] <> "/"))
    end)
  end

  defp entry_errors(errors, expected_entries, actual_entries) do
    expected = Map.new(expected_entries, &{&1["path"], &1})
    actual = Map.new(actual_entries, &{&1["path"], &1})
    paths = Enum.sort(Enum.uniq(Map.keys(expected) ++ Map.keys(actual)))

    Enum.reduce(paths, errors, fn path, acc ->
      case {Map.get(expected, path), Map.get(actual, path)} do
        {nil, _} ->
          ["archive contains undeclared manifest entry #{path}" | acc]

        {_, nil} ->
          ["archive is missing manifest entry #{path}" | acc]

        {expected_entry, actual_entry} ->
          Enum.reduce(~w(kind mode size sha256 link_target), acc, fn field, field_errors ->
            mismatch(
              field_errors,
              "#{path} #{field}",
              expected_entry[field],
              actual_entry[field]
            )
          end)
      end
    end)
  end

  defp mismatch(errors, _, expected, actual) when expected == actual, do: errors

  defp mismatch(errors, field, expected, actual),
    do: ["#{field} mismatch: expected #{inspect(expected)}, got #{inspect(actual)}" | errors]

  defp wrap({:ok, value}), do: {:ok, value}
  defp wrap({:error, errors}) when is_list(errors), do: {:error, errors}
  defp wrap({:error, error}), do: {:error, [error]}
end
