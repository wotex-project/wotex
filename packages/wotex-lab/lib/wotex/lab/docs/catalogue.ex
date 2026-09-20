defmodule Wotex.Lab.Docs.Catalogue do
  @moduledoc """
  Validates the closed source cohort for the generated Wotex documentation.

  Membership is explicit. Filesystem discovery cannot add a package, and local
  task state is rejected even when a caller tries to place it inside a declared
  documentation root.
  """

  @schema "wotex-documentation-cohort/v1"
  @source_ids ~w(
    wotex wotex-runtime wotex-binding-http wotex-binding-mqtt
    wotex-modbus wotex-coap wotex-bacnet wotex-opcua wotex-ble
    wotex-matter wotex-thread wotex-directory wotex-continuum
    wotex-nx wotex-conformance wotex-lab family-docs wotex-dot
  )
  @root_keys ~w(schema_version profile tree_digest_algorithm sources)
  @source_keys ~w(id title repository_url repository_path kind hex_package version
                   documentation_roots default_branch revision tree_digest license
                   build_command expected_collection_digest)
  @digest ~r/\Asha256:[0-9a-f]{64}\z/
  @revision ~r/\A[0-9a-f]{40}\z/
  @identifier ~r/\A[a-z0-9][a-z0-9-]*\z/

  @typedoc "A validated decoded catalogue."
  @type t :: map()

  @doc "The exact accepted source IDs in deterministic build order."
  @spec source_ids() :: [String.t()]
  def source_ids, do: @source_ids

  @doc "The package-owned default catalogue path."
  @spec default_path() :: Path.t()
  def default_path, do: Application.app_dir(:wotex_lab, "priv/documentation/cohort.json")

  @doc "Reads and validates a cohort file without resolving a network source."
  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(path \\ default_path()) do
    with {:ok, bytes} <- File.read(path),
         {:ok, decoded} <- JSON.decode(bytes),
         :ok <- validate(decoded) do
      {:ok, decoded}
    end
  end

  @doc "Validates the closed cohort schema and exact membership."
  @spec validate(term()) :: :ok | {:error, term()}
  def validate(%{"schema_version" => @schema, "sources" => sources} = catalogue)
      when is_list(sources) do
    with :ok <- closed(catalogue, @root_keys, :catalogue),
         true <- catalogue["profile"] in ["release", "rolling"],
         true <- catalogue["tree_digest_algorithm"] == "sha256-git-ls-tree-v1",
         true <- Enum.map(sources, & &1["id"]) == @source_ids,
         :ok <- validate_sources(sources) do
      :ok
    else
      false -> {:error, :invalid_documentation_cohort}
      {:error, _} = error -> error
    end
  end

  def validate(%{"schema_version" => version}),
    do: {:error, {:unsupported_documentation_cohort, version}}

  def validate(_), do: {:error, :invalid_documentation_cohort}

  @doc "Requires every source to carry its candidate collection digest."
  @spec validate_locked(t()) :: :ok | {:error, term()}
  def validate_locked(%{"sources" => sources} = catalogue) do
    with :ok <- validate(catalogue) do
      case Enum.find(sources, &(not digest?(&1["expected_collection_digest"]))) do
        nil -> :ok
        source -> {:error, {:unlocked_documentation_source, source["id"]}}
      end
    end
  end

  @doc "Returns one admitted source by exact ID."
  @spec fetch(t(), String.t()) :: {:ok, map()} | :error
  def fetch(%{"sources" => sources}, id) when id in @source_ids do
    case Enum.find(sources, &(&1["id"] == id)) do
      nil -> :error
      source -> {:ok, source}
    end
  end

  def fetch(_, _), do: :error

  defp validate_sources(sources) do
    Enum.reduce_while(sources, :ok, fn source, :ok ->
      case validate_source(source) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp validate_source(source) when is_map(source) do
    with :ok <- closed(source, @source_keys, {:source, source["id"]}),
         true <- Regex.match?(@identifier, source["id"] || ""),
         true <- nonempty?(source["title"]),
         true <- https_repository?(source["repository_url"]),
         true <- relative_path?(source["repository_path"]),
         true <- source["kind"] in ["mix_package", "documentation"],
         true <- package_identity?(source),
         true <- nonempty?(source["version"]),
         true <- roots?(source["documentation_roots"]),
         true <- source["default_branch"] == "main",
         true <- Regex.match?(@revision, source["revision"] || ""),
         true <- digest?(source["tree_digest"]),
         true <- nonempty?(source["license"]),
         true <- command?(source),
         true <-
           is_nil(source["expected_collection_digest"]) or
             digest?(source["expected_collection_digest"]) do
      :ok
    else
      false -> {:error, {:invalid_documentation_source, source["id"]}}
      {:error, _} = error -> error
    end
  end

  defp validate_source(source), do: {:error, {:invalid_documentation_source, source}}

  defp closed(value, keys, context) do
    unknown = Map.keys(value) -- keys
    missing = keys -- Map.keys(value)

    if unknown == [] and missing == [],
      do: :ok,
      else: {:error, {:invalid_documentation_keys, context, unknown, missing}}
  end

  defp package_identity?(%{"kind" => "mix_package", "id" => id, "hex_package" => package}) do
    package == String.replace(id, "-", "_")
  end

  defp package_identity?(%{"kind" => "documentation", "hex_package" => nil}), do: true
  defp package_identity?(_), do: false

  defp roots?(roots) when is_list(roots) and roots != [] do
    roots == Enum.uniq(roots) and
      Enum.all?(roots, &(relative_path?(&1) and not String.starts_with?(&1, "docs/tasks/local")))
  end

  defp roots?(_), do: false

  defp command?(%{"kind" => "mix_package", "build_command" => command}),
    do: command == ["mix", "doc_shell.build", "--no-start"]

  defp command?(%{"kind" => "documentation", "id" => id, "build_command" => command}) do
    command == ["mix", "run", "--no-start", "bin/build.exs", "--source", id]
  end

  defp command?(_), do: false

  defp relative_path?(path) when is_binary(path) and path != "" do
    Path.type(path) == :relative and ".." not in Path.split(path) and
      not String.contains?(path, <<0>>)
  end

  defp relative_path?(_), do: false

  defp https_repository?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: "github.com", query: nil, fragment: nil} -> true
      _ -> false
    end
  end

  defp https_repository?(_), do: false
  defp digest?(value) when is_binary(value), do: Regex.match?(@digest, value)
  defp digest?(_), do: false
  defp nonempty?(value), do: is_binary(value) and value != "" and String.valid?(value)
end
