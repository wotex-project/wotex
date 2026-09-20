defmodule Wotex.Workspace.NativeArtifact.Inventory do
  @moduledoc "Loads the closed native artifact inventory from the root manifest."

  alias Wotex.Workspace
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeArtifact.Descriptor

  @doc "Loads every explicitly admitted descriptor, sorted by package and profile."
  @spec load(Manifest.t(), Path.t()) :: {:ok, [Descriptor.t()]} | {:error, [String.t()]}
  def load(%Manifest{} = manifest \\ Manifest.load!(), root \\ Workspace.root()) do
    results =
      for package <- Manifest.packages(manifest),
          admission <- Enum.sort_by(package.native_artifacts, & &1.profile) do
        relative = Path.join(Manifest.path(package.name, manifest), admission.descriptor)
        Descriptor.load(relative, admission, package, manifest, root)
      end

    errors = for {:error, message} <- results, do: message

    if errors == [] do
      descriptors = for {:ok, descriptor} <- results, do: descriptor
      validate_inventory(descriptors, manifest)
    else
      {:error, errors}
    end
  end

  @doc "Fetches one package/profile descriptor."
  @spec fetch([Descriptor.t()], String.t(), String.t()) ::
          {:ok, Descriptor.t()} | {:error, String.t()}
  def fetch(descriptors, package, profile) do
    case Enum.find(descriptors, &(&1.package == package and &1.profile == profile)) do
      nil -> {:error, "undeclared native artifact profile #{package}/#{profile}"}
      descriptor -> {:ok, descriptor}
    end
  end

  defp validate_inventory(descriptors, manifest) do
    identities = Enum.map(descriptors, &{&1.package, &1.profile})

    if Enum.uniq(identities) != identities,
      do: {:error, ["native artifact descriptors repeat a package/profile identity"]},
      else: validate_smoke(descriptors, manifest)
  end

  defp validate_smoke(descriptors, manifest) do
    errors =
      Enum.flat_map(manifest.native_artifact.smoke, fn cell ->
        with {:ok, descriptor} <- fetch(descriptors, cell.package, cell.profile),
             {:ok, %{status: :supported}} <- Descriptor.target(descriptor, cell.target) do
          []
        else
          {:ok, %{status: :unsupported}} ->
            [
              "native artifact smoke cell #{cell.package}/#{cell.profile}/#{cell.target} is unsupported"
            ]

          {:error, message} ->
            [
              "native artifact smoke cell #{cell.package}/#{cell.profile}/#{cell.target}: #{message}"
            ]
        end
      end)

    if errors == [], do: {:ok, descriptors}, else: {:error, errors}
  end
end
