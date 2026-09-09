defmodule Wotex.Lab.MCP.Resources do
  @moduledoc """
  Read-only MCP resources: package, spec, seam, scenario, Thing and evidence
  metadata that already exists in the package or in the explicit Lab instance.

  URIs use the `wotex-lab://` scheme. Catalogue, plan and provenance documents
  are embedded verbatim at compile time (the YAML catalogue as text, the
  provenance index as JSON), so they are served from the compiled package
  without a source tree; fixture manifests and models come from `priv`; design
  tokens, seam ownership and scenario descriptors are Lab data; Things are the
  reference hosts of the session's instance, described by their own Thing
  Description. Nothing is fetched from the network and nothing is executed.
  """

  alias Wotex.Lab.DesignSystem
  alias Wotex.Lab.MCP.Seams
  alias Wotex.Lab.Reference.Thing
  alias Wotex.ThingDescription

  @max_file_bytes 1_048_576
  @root Path.expand("../../../..", __DIR__)
  @documents %{
    "docs/specs/catalogue.yaml" => Path.join(@root, "docs/specs/catalogue.yaml"),
    "docs/plans/wotex-lab-completion.md" => Path.join(@root, "docs/plans/wotex-lab-completion.md"),
    "docs/provenance/source-index.json" => Path.join(@root, "docs/provenance/source-index.json"),
    "docs/provenance/source-cohort.json" => Path.join(@root, "docs/provenance/source-cohort.json"),
    "docs/provenance/standards-and-dependencies.md" =>
      Path.join(@root, "docs/provenance/standards-and-dependencies.md")
  }
  for {_, absolute} <- @documents, do: @external_resource(absolute)
  @embedded Map.new(@documents, fn {relative, absolute} -> {relative, File.read!(absolute)} end)

  @static [
    {"wotex-lab://catalogue", "Specification catalogue", "text/yaml",
     {:doc, "docs/specs/catalogue.yaml"}},
    {"wotex-lab://completion-plan", "Completion contract", "text/markdown",
     {:doc, "docs/plans/wotex-lab-completion.md"}},
    {"wotex-lab://provenance/source-index", "Historical source inspection baseline",
     "application/json", {:doc, "docs/provenance/source-index.json"}},
    {"wotex-lab://provenance/source-cohort", "Source content digests", "application/json",
     {:doc, "docs/provenance/source-cohort.json"}},
    {"wotex-lab://provenance/standards", "Standards and dependencies", "text/markdown",
     {:doc, "docs/provenance/standards-and-dependencies.md"}},
    {"wotex-lab://fixtures/loopback", "Loopback fixture manifest", "application/json",
     {:priv, "priv/fixtures/loopback/manifest.json"}},
    {"wotex-lab://fixtures/thermal", "Thermal fixture manifest", "application/json",
     {:priv, "priv/fixtures/thermal/manifest.json"}},
    {"wotex-lab://models", "Formal model manifest", "application/json",
     {:priv, "priv/models/manifest.json"}},
    {"wotex-lab://design-tokens", "Design system tokens", "application/json", :tokens},
    {"wotex-lab://seams", "Ownership seams", "application/json", :seams}
  ]

  @doc "Lists every resource the session can read."
  @spec list(map()) :: [map()]
  def list(state) do
    static =
      Enum.map(@static, fn {uri, name, mime, _} ->
        %{"uri" => uri, "name" => name, "mimeType" => mime}
      end)

    static ++ things(state)
  end

  @doc "Reads one resource."
  @spec read(map(), String.t()) :: {:ok, [map()]} | {:error, integer(), String.t()}
  def read(state, uri) do
    case List.keyfind(@static, uri, 0) do
      {^uri, _, mime, source} -> content(uri, mime, source)
      nil -> thing(state, uri)
    end
  end

  defp content(uri, mime, {:doc, relative}),
    do: {:ok, [%{"uri" => uri, "mimeType" => mime, "text" => Map.fetch!(@embedded, relative)}]}

  defp content(uri, mime, {:priv, relative}),
    do: file(uri, mime, Path.join(package_dir(), relative))

  defp content(uri, mime, :tokens) do
    {:ok, text} =
      Wotex.JSON.encode(%{"version" => DesignSystem.version(), "tokens" => DesignSystem.tokens()})

    {:ok, [%{"uri" => uri, "mimeType" => mime, "text" => text}]}
  end

  defp content(uri, mime, :seams) do
    {:ok, text} = Wotex.JSON.encode(Seams.all())
    {:ok, [%{"uri" => uri, "mimeType" => mime, "text" => text}]}
  end

  defp file(uri, mime, path) do
    with {:ok, %File.Stat{size: size}} when size <= @max_file_bytes <- File.stat(path),
         {:ok, text} <- File.read(path) do
      {:ok, [%{"uri" => uri, "mimeType" => mime, "text" => text}]}
    else
      {:ok, _} -> {:error, -32_000, "resource exceeds the size ceiling"}
      {:error, _} -> {:error, -32_002, "resource is not available in this package"}
    end
  end

  defp package_dir, do: Application.app_dir(:wotex_lab)

  defp things(%{instance: instance}) when is_pid(instance) do
    instance
    |> reference_things()
    |> Enum.map(fn {id, _} ->
      %{
        "uri" => "wotex-lab://things/" <> id,
        "name" => "Simulated Thing " <> id,
        "mimeType" => "application/td+json"
      }
    end)
  end

  defp things(_), do: []

  defp thing(state, "wotex-lab://things/" <> id) do
    case fetch_thing(state, id) do
      {:ok, pid} ->
        {:ok, text} =
          pid
          |> Thing.thing_description()
          |> ThingDescription.to_map()
          |> Wotex.JSON.encode()

        {:ok,
         [
           %{
             "uri" => "wotex-lab://things/" <> id,
             "mimeType" => "application/td+json",
             "text" => text
           }
         ]}

      :error ->
        {:error, -32_002, "no such simulated Thing in this instance"}
    end
  end

  defp thing(_, _), do: {:error, -32_002, "unknown resource"}

  @doc false
  @spec fetch_thing(map(), String.t()) :: {:ok, pid()} | :error
  def fetch_thing(%{instance: instance}, id) when is_pid(instance) and is_binary(id) do
    case List.keyfind(reference_things(instance), id, 0) do
      {^id, pid} -> {:ok, pid}
      nil -> :error
    end
  end

  def fetch_thing(_, _), do: :error

  @doc false
  @spec reference_things(pid()) :: [{String.t(), pid()}]
  def reference_things(instance) do
    case List.keyfind(Supervisor.which_children(instance), :things, 0) do
      {:things, things, :supervisor, _} ->
        things
        |> DynamicSupervisor.which_children()
        |> Enum.flat_map(&reference_thing/1)

      _ ->
        []
    end
  end

  defp reference_thing({_, pid, :worker, [Thing]}) when is_pid(pid),
    do: [{pid |> Thing.thing_description() |> ThingDescription.id(), pid}]

  defp reference_thing(_), do: []
end
