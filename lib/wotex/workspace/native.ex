defmodule Wotex.Workspace.Native do
  @moduledoc """
  Pinned native sources of the native packages.

  `sources/2` reads each native package's pinned-source manifest when it has
  one of the known shapes, lists the upstream pins and verifies the sha256
  digest of every pinned file that is present locally. Known shapes:

    * `native/**/source.json` with a `schema` of the form
      `wotex.<package>.<upstream>-source@1` (for example
      `packages/wotex-coap/native/oscore/source.json`): one upstream pin
      (`version`, `commit`, `url`, `sha256`) plus `patches[]`, `files` and
      `patched_sources` digests relative to the manifest directory;
    * `priv/fixtures/native-sources-v1.json` with
      `format: wotex.native.sources` (for example in `packages/wotex-opcua`):
      `sources[]` and `vendored_sources[]` pins, `sdk_patches[]` and
      `vendored_sources[].files[]` digests relative to `priv/native/`;
    * `test/support/software/sources.json` with `archives[]` (for example in
      `packages/wotex-matter`): one pin per archive, nothing local.

  A native package without a manifest of a known shape is reported as
  `no manifest`; that is not a failure.

  `advisories/3` queries OSV for every pin. `build/4` dispatches a
  package's own `native_task` with an absolute workspace.
  """

  alias Wotex.Workspace
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Runner

  @osv_url "https://api.osv.dev/v1/query"

  @type pin :: %{
          name: String.t(),
          version: String.t() | nil,
          commit: String.t() | nil,
          url: String.t() | nil,
          sha256: String.t() | nil,
          manifest: Path.t()
        }

  @type report :: %{
          package: String.t(),
          status: :ok | :no_manifest | :error,
          manifests: [Path.t()],
          pins: [pin()],
          verified: [Path.t()],
          absent: [Path.t()],
          problems: [String.t()]
        }

  @type vulnerability :: %{id: String.t(), summary: String.t()}

  @type advisory_result :: %{pin: pin(), result: {:ok, [vulnerability()]} | {:error, String.t()}}

  @doc "One report per native package, sorted by package name."
  @spec sources(Manifest.t(), Path.t()) :: [report()]
  def sources(%Manifest{} = manifest \\ Manifest.load!(), root \\ Workspace.root()) do
    manifest
    |> Manifest.native_packages()
    |> Enum.map(&package_report(&1, root))
  end

  @doc "Whether no report failed."
  @spec sources_ok?([report()]) :: boolean()
  def sources_ok?(reports), do: Enum.all?(reports, &(&1.status != :error))

  @doc """
  Queries OSV for every pin of `reports`. `query:` replaces the HTTP query
  (tests); `offline: true` performs no query and returns `[]`.
  """
  @spec advisories([report()], keyword()) :: [advisory_result()]
  def advisories(reports, opts \\ []) do
    if Keyword.get(opts, :offline, false) do
      []
    else
      query = Keyword.get(opts, :query, &osv_query/1)

      reports
      |> pins()
      |> Enum.map(&%{pin: &1, result: query.(&1)})
    end
  end

  @doc "The distinct pins of `reports`, in report order."
  @spec pins([report()]) :: [pin()]
  def pins(reports) do
    reports
    |> Enum.flat_map(& &1.pins)
    |> Enum.uniq_by(&{&1.name, &1.version, &1.commit})
  end

  @doc "Whether advisory results contain a vulnerability or a failed query."
  @spec advisories_clean?([advisory_result()]) :: boolean()
  def advisories_clean?(results) do
    Enum.all?(results, &match?(%{result: {:ok, []}}, &1))
  end

  @doc "The OSV request body for a pin: by commit when pinned, else by name and version."
  @spec osv_body(pin()) :: map()
  def osv_body(%{commit: commit}) when is_binary(commit) and commit != "", do: %{"commit" => commit}

  def osv_body(%{name: name, version: version}),
    do: %{"version" => version, "package" => %{"name" => name}}

  @doc "Queries OSV over HTTPS."
  @spec osv_query(pin()) :: {:ok, [vulnerability()]} | {:error, String.t()}
  def osv_query(pin) do
    with {:ok, _} <- Application.ensure_all_started([:inets, :ssl]) do
      request =
        {String.to_charlist(@osv_url), [], ~c"application/json", JSON.encode!(osv_body(pin))}

      http_options = [
        timeout: 30_000,
        ssl: [
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          depth: 3,
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]
      ]

      case :httpc.request(:post, request, http_options, body_format: :binary) do
        {:ok, {{_, 200, _}, _, body}} ->
          decode_vulnerabilities(body)

        {:ok, {{_, status, _}, _, body}} ->
          {:error, "OSV returned #{status}: #{body}"}

        {:error, reason} ->
          {:error, "OSV request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Runs the package's `native_task` with `--workspace <absolute dir>` and
  returns its exit status. A relative workspace is refused.
  """
  @spec build(String.t(), Path.t(), Manifest.t(), Path.t()) ::
          {:ok, non_neg_integer()} | {:error, String.t()}
  def build(name, workspace, %Manifest{} = manifest \\ Manifest.load!(), root \\ Workspace.root()) do
    with :ok <- check_workspace(workspace),
         {:ok, package} <- fetch(name, manifest),
         {:ok, task} <- native_task(package) do
      path = Manifest.absolute_path(name, manifest, root)
      {:ok, Runner.run(path, [task, "--workspace", workspace])}
    end
  end

  @doc "Computes the lowercase hex sha256 of a file."
  @spec sha256(Path.t()) :: String.t()
  def sha256(path), do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

  # Reports

  defp package_report(package, root) do
    package_path = Path.join(root, "packages/#{package.name}")

    manifests =
      source_json_manifests(package_path, root) ++
        native_sources_manifest(package_path, root) ++ archives_manifest(package_path, root)

    parts = Enum.map(manifests, &read_manifest(&1, root))
    problems = Enum.flat_map(parts, & &1.problems)

    status =
      cond do
        parts == [] -> :no_manifest
        problems == [] -> :ok
        true -> :error
      end

    %{
      package: package.name,
      status: status,
      manifests: Enum.map(parts, & &1.manifest),
      pins: Enum.flat_map(parts, & &1.pins),
      verified: Enum.flat_map(parts, & &1.verified),
      absent: Enum.flat_map(parts, & &1.absent),
      problems: problems
    }
  end

  defp read_manifest({relative, absolute, shape}, root) do
    case read_json(absolute) do
      {:ok, json} ->
        {pins, digests} = extract(shape, json, relative, absolute)
        {verified, absent, problems} = verify(digests, root)
        %{manifest: relative, pins: pins, verified: verified, absent: absent, problems: problems}

      {:error, message} ->
        %{
          manifest: relative,
          pins: [],
          verified: [],
          absent: [],
          problems: ["#{relative}: #{message}"]
        }
    end
  end

  defp source_json_manifests(package_path, root) do
    package_path
    |> Path.join("native/**/source.json")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(fn absolute ->
      relative = Path.relative_to(absolute, root)

      case read_json(absolute) do
        {:ok, %{"schema" => schema}} when is_binary(schema) ->
          case Regex.run(~r/^wotex\.[a-z0-9_]+\.([a-z0-9_-]+)-source@1$/, schema) do
            [_, upstream] -> [{relative, absolute, {:source_json, upstream}}]
            nil -> []
          end

        _ ->
          []
      end
    end)
  end

  defp native_sources_manifest(package_path, root) do
    absolute = Path.join(package_path, "priv/fixtures/native-sources-v1.json")

    case read_json(absolute) do
      {:ok, %{"format" => "wotex.native.sources"}} ->
        [
          {Path.relative_to(absolute, root), absolute,
           {:native_sources, Path.join(package_path, "priv/native")}}
        ]

      _ ->
        []
    end
  end

  defp archives_manifest(package_path, root) do
    absolute = Path.join(package_path, "test/support/software/sources.json")

    case read_json(absolute) do
      {:ok, %{"archives" => archives}} when is_list(archives) ->
        [{Path.relative_to(absolute, root), absolute, :archives}]

      _ ->
        []
    end
  end

  defp extract({:source_json, upstream}, json, relative, absolute) do
    dir = Path.dirname(absolute)
    pin = pin(upstream, json["version"], json["commit"], json["url"], json["sha256"], relative)

    digests =
      entries(json["patches"], dir) ++
        map_digests(json["files"], dir) ++
        map_digests(json["patched_sources"], dir)

    {[pin], digests}
  end

  defp extract({:native_sources, base}, json, relative, _) do
    sources = List.wrap(json["sources"]) ++ List.wrap(json["vendored_sources"])

    pins =
      for %{"name" => name} = source <- sources,
          do:
            pin(
              name,
              source["version"],
              source["commit"],
              source["url"],
              source["sha256"],
              relative
            )

    vendored_files = Enum.flat_map(List.wrap(json["vendored_sources"]), &List.wrap(&1["files"]))
    {pins, entries(json["sdk_patches"], base) ++ entries(vendored_files, base)}
  end

  defp extract(:archives, json, relative, _) do
    pins =
      for %{"name" => name} = archive <- List.wrap(json["archives"]),
          do:
            pin(
              name,
              archive["version"],
              archive["revision"],
              archive["url"],
              archive["sha256"],
              relative
            )

    {pins, []}
  end

  defp pin(name, version, commit, url, sha256, manifest) do
    %{name: name, version: version, commit: commit, url: url, sha256: sha256, manifest: manifest}
  end

  defp entries(nil, _), do: []

  defp entries(list, dir) when is_list(list) do
    for %{"path" => path, "sha256" => sha256} <- list,
        is_binary(path) and is_binary(sha256),
        do: {Path.join(dir, path), sha256}
  end

  defp entries(_, _), do: []

  defp map_digests(map, dir) when is_map(map) do
    for {path, sha256} <- Enum.sort(map), is_binary(sha256), do: {Path.join(dir, path), sha256}
  end

  defp map_digests(_, _), do: []

  defp verify(digests, root) do
    Enum.reduce(digests, {[], [], []}, fn {absolute, expected}, {verified, absent, problems} ->
      relative = Path.relative_to(absolute, root)

      cond do
        not File.regular?(absolute) ->
          {verified, [relative | absent], problems}

        sha256(absolute) == String.downcase(expected) ->
          {[relative | verified], absent, problems}

        true ->
          {verified, absent, ["#{relative}: sha256 mismatch" | problems]}
      end
    end)
    |> then(fn {verified, absent, problems} ->
      {Enum.reverse(verified), Enum.reverse(absent), Enum.reverse(problems)}
    end)
  end

  defp read_json(absolute) do
    with {:ok, text} <- File.read(absolute),
         {:ok, json} <- JSON.decode(text) do
      {:ok, json}
    else
      {:error, reason} when is_atom(reason) -> {:error, :file.format_error(reason) |> to_string()}
      {:error, reason} -> {:error, "invalid JSON (#{inspect(reason)})"}
    end
  end

  defp decode_vulnerabilities(body) do
    case JSON.decode(body) do
      {:ok, %{"vulns" => vulns}} when is_list(vulns) ->
        {:ok, Enum.map(vulns, &%{id: &1["id"] || "?", summary: &1["summary"] || ""})}

      {:ok, %{}} ->
        {:ok, []}

      _ ->
        {:error, "OSV returned an unexpected body"}
    end
  end

  defp check_workspace(workspace) do
    if Path.type(workspace) == :absolute,
      do: :ok,
      else: {:error, "workspace must be an absolute directory, got #{inspect(workspace)}"}
  end

  defp fetch(name, manifest) do
    case Manifest.fetch(name, manifest) do
      {:ok, package} -> {:ok, package}
      :error -> {:error, "unknown package #{inspect(name)}"}
    end
  end

  defp native_task(%{native_task: task}) when is_binary(task), do: {:ok, task}
  defp native_task(%{name: name}), do: {:error, "package #{name} declares no native_task"}
end
