defmodule Wotex.Workspace.NativeArtifact.Descriptor do
  @moduledoc """
  A package-owned descriptor admitted explicitly by `tooling/packages.yaml`.

  Loading is data-only: it decodes JSON and validates the closed schema without
  compiling or starting the owning package.
  """

  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeArtifact.CanonicalJSON

  @schema "wotex.native-artifact-descriptor@2"
  @artifact_format "wotex.native-artifact@1"
  @digest ~r/^[0-9a-f]{64}$/
  @name ~r/^[a-z][a-z0-9-]*$/
  @task ~r/^[a-z][a-z0-9_.-]*$/

  @required ~w(schema artifact_format package profile kind targets sources patches toolchain build qualification outputs compatibility external_libraries legal native_inputs retrieval)
  @forbidden_key ~r/(credential|password|secret|access[_-]?token|cache[_-]?(path|root)|publication|published)/i

  @type target_support :: %{
          name: String.t(),
          status: :supported | :unsupported,
          reason: String.t() | nil
        }

  @type t :: %__MODULE__{
          path: Path.t() | nil,
          package: String.t(),
          profile: String.t(),
          kind: String.t(),
          targets: [target_support()],
          raw: map()
        }

  @enforce_keys [:package, :profile, :kind, :targets, :raw]
  defstruct [:path, :package, :profile, :kind, :targets, :raw]

  @doc "The accepted descriptor schema."
  @spec schema() :: String.t()
  def schema, do: @schema

  @doc "The accepted artifact format."
  @spec artifact_format() :: String.t()
  def artifact_format, do: @artifact_format

  @doc "Loads and validates one admitted descriptor."
  @spec load(
          Path.t(),
          Manifest.NativeArtifactProfile.t(),
          Manifest.Package.t(),
          Manifest.t(),
          Path.t()
        ) ::
          {:ok, t()} | {:error, String.t()}
  def load(path, admission, package, %Manifest{} = manifest, root) do
    absolute = Path.join(root, path)

    with {:ok, bytes} <- File.read(absolute),
         {:ok, decoded} <- decode(bytes),
         {:ok, descriptor} <- from_map(decoded, manifest, path),
         :ok <- admitted?(descriptor, admission, package) do
      {:ok, descriptor}
    else
      {:error, message} -> {:error, "#{path}: #{message}"}
    end
  end

  @doc "Validates a decoded descriptor map."
  @spec from_map(term(), Manifest.t(), Path.t() | nil) :: {:ok, t()} | {:error, String.t()}
  def from_map(map, manifest, path \\ nil)

  def from_map(map, %Manifest{} = manifest, path) when is_map(map) do
    with :ok <- exact_fields(map, @required, "$"),
         :ok <- exact_value(map, "schema", @schema),
         :ok <- exact_value(map, "artifact_format", @artifact_format),
         :ok <- safe_values(map, "$"),
         {:ok, package} <- name(map["package"], "$.package"),
         {:ok, profile} <- name(map["profile"], "$.profile"),
         {:ok, kind} <- name(map["kind"], "$.kind"),
         {:ok, targets} <- targets(map["targets"], manifest),
         :ok <- sources(map["sources"]),
         :ok <- patches(map["patches"]),
         :ok <- toolchain(map["toolchain"]),
         :ok <- operation(map["build"], "$.build"),
         :ok <- operation(map["qualification"], "$.qualification"),
         :ok <- outputs(map["outputs"]),
         :ok <- identity_value(map["compatibility"], "$.compatibility"),
         :ok <- strings(map["external_libraries"], "$.external_libraries"),
         :ok <- paths(map["legal"], "$.legal", false),
         :ok <- native_inputs(map["native_inputs"]),
         :ok <- retrieval(map["retrieval"]),
         {:ok, raw} <- normalize(map) do
      {:ok,
       %__MODULE__{
         path: path,
         package: package,
         profile: profile,
         kind: kind,
         targets: targets,
         raw: raw
       }}
    end
  end

  def from_map(_, _, _), do: {:error, "$: descriptor must be a JSON object"}

  @doc "Returns one descriptor target or an explicit undeclared-target error."
  @spec target(t(), String.t()) :: {:ok, target_support()} | {:error, String.t()}
  def target(%__MODULE__{targets: targets}, name) do
    case Enum.find(targets, &(&1.name == name)) do
      nil -> {:error, "target #{inspect(name)} is not declared by the descriptor"}
      target -> {:ok, target}
    end
  end

  defp decode(bytes) do
    case JSON.decode(bytes) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, error} -> {:error, "invalid JSON: #{Exception.message(error)}"}
    end
  rescue
    error -> {:error, "invalid JSON: #{Exception.message(error)}"}
  end

  defp admitted?(descriptor, admission, package) do
    cond do
      descriptor.package != package.name ->
        {:error, "$.package: expected #{inspect(package.name)}"}

      descriptor.profile != admission.profile ->
        {:error, "$.profile: expected #{inspect(admission.profile)}"}

      true ->
        :ok
    end
  end

  defp exact_fields(map, fields, path) do
    missing = fields -- Map.keys(map)
    unknown = Map.keys(map) -- fields

    cond do
      missing != [] ->
        {:error, "#{path}: missing required fields: #{Enum.join(Enum.sort(missing), ", ")}"}

      unknown != [] ->
        {:error, "#{path}: unknown fields: #{Enum.join(Enum.sort(unknown), ", ")}"}

      true ->
        :ok
    end
  end

  defp exact_value(map, key, value) do
    if map[key] == value,
      do: :ok,
      else: {:error, "$.#{key}: expected #{inspect(value)}, got #{inspect(map[key])}"}
  end

  defp name(value, path) when is_binary(value) do
    if Regex.match?(@name, value),
      do: {:ok, value},
      else: {:error, "#{path}: invalid lowercase name"}
  end

  defp name(_, path), do: {:error, "#{path}: expected a string"}

  defp targets(value, manifest) when is_list(value) and value != [] do
    parsed = Enum.with_index(value) |> Enum.map(&target_entry(&1, manifest))

    case Enum.find(parsed, &match?({:error, _}, &1)) do
      nil ->
        targets = Enum.map(parsed, &elem(&1, 1))

        if Enum.uniq_by(targets, & &1.name) == targets,
          do: {:ok, Enum.sort_by(targets, & &1.name)},
          else: {:error, "$.targets: duplicate or contradictory target declarations"}

      {:error, _} = error ->
        error
    end
  end

  defp targets(_, _), do: {:error, "$.targets: expected a non-empty list"}

  defp target_entry({entry, index}, manifest) when is_map(entry) do
    path = "$.targets[#{index}]"
    status = entry["status"]
    fields = if status == "unsupported", do: ~w(name status reason), else: ~w(name status)

    with :ok <- exact_fields(entry, fields, path),
         {:ok, name} <- name(entry["name"], "#{path}.name"),
         :ok <-
           ensure(
             Map.has_key?(manifest.native_artifact.targets, name),
             "#{path}.name: undeclared target #{inspect(name)}"
           ),
         {:ok, parsed_status, reason} <- target_status(status, entry["reason"], path) do
      {:ok, %{name: name, status: parsed_status, reason: reason}}
    else
      {:error, _} = error -> error
    end
  end

  defp target_entry({_, index}, _), do: {:error, "$.targets[#{index}]: expected an object"}

  defp target_status("supported", nil, _), do: {:ok, :supported, nil}

  defp target_status("unsupported", reason, _) when is_binary(reason) and reason != "",
    do: {:ok, :unsupported, reason}

  defp target_status(_, _, path),
    do: {:error, "#{path}: status must be supported, or unsupported with a non-empty reason"}

  defp sources(%{"first_party" => first_party, "upstream" => upstream} = sources) do
    with :ok <- exact_fields(sources, ~w(first_party upstream), "$.sources"),
         :ok <- paths(first_party, "$.sources.first_party", false) do
      upstream(upstream)
    end
  end

  defp sources(_), do: {:error, "$.sources: expected first_party and upstream"}

  defp upstream(value) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {entry, index}, :ok ->
      path = "$.sources.upstream[#{index}]"

      case entry do
        %{"name" => source_name, "url" => url, "revision" => revision, "sha256" => digest} ->
          with :ok <- exact_fields(entry, ~w(name url revision sha256), path),
               {:ok, _} <- name(source_name, "#{path}.name"),
               true <- immutable_url?(url) or {:error, "#{path}.url: expected immutable HTTPS URL"},
               true <-
                 immutable_revision?(revision) or
                   {:error, "#{path}.revision: mutable or invalid revision"},
               true <-
                 digest?(digest) or {:error, "#{path}.sha256: expected full lowercase SHA-256"} do
            {:cont, :ok}
          else
            {:error, _} = error -> {:halt, error}
          end

        _ ->
          {:halt, {:error, "#{path}: expected name, url, revision and sha256"}}
      end
    end)
  end

  defp upstream(_), do: {:error, "$.sources.upstream: expected a list"}

  defp patches(value) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {entry, index}, :ok ->
      path = "$.patches[#{index}]"

      case entry do
        %{"id" => id, "path" => patch_path, "sha256" => digest} ->
          with :ok <- exact_fields(entry, ~w(id path sha256), path),
               {:ok, _} <- name(id, "#{path}.id"),
               true <-
                 relative?(patch_path) or
                   {:error, "#{path}.path: expected a normalized relative path"},
               true <-
                 digest?(digest) or {:error, "#{path}.sha256: expected full lowercase SHA-256"} do
            {:cont, :ok}
          else
            {:error, _} = error -> {:halt, error}
          end

        _ ->
          {:halt, {:error, "#{path}: expected id, path and sha256"}}
      end
    end)
  end

  defp patches(_), do: {:error, "$.patches: expected a list"}

  defp toolchain(
         %{"inputs" => inputs, "requirements" => requirements, "container_digest" => container} =
           value
       ) do
    with :ok <- exact_fields(value, ~w(inputs requirements container_digest), "$.toolchain"),
         :ok <- paths(inputs, "$.toolchain.inputs", true),
         :ok <- identity_value(requirements, "$.toolchain.requirements") do
      container_digest(container)
    end
  end

  defp toolchain(_),
    do: {:error, "$.toolchain: expected inputs, requirements and container_digest"}

  defp container_digest(nil), do: :ok

  defp container_digest("sha256:" <> digest),
    do: if(digest?(digest), do: :ok, else: {:error, "$.toolchain.container_digest: invalid digest"})

  defp container_digest(_),
    do: {:error, "$.toolchain.container_digest: expected null or sha256:<full digest>"}

  defp operation(%{"task" => task, "options" => options, "features" => features} = value, path) do
    with :ok <- exact_fields(value, ~w(task options features), path),
         :ok <-
           ensure(
             is_binary(task) and Regex.match?(@task, task),
             "#{path}.task: invalid task name"
           ),
         :ok <- identity_value(options, "#{path}.options"),
         :ok <- strings(features, "#{path}.features") do
      :ok
    else
      {:error, _} = error -> error
    end
  end

  defp operation(_, path), do: {:error, "#{path}: expected task, options and features"}

  defp outputs(value) when is_list(value) and value != [] do
    result =
      value
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, MapSet.new()}, fn {entry, index}, {:ok, seen} ->
        path = "$.outputs[#{index}]"

        case entry do
          %{"path" => output, "kind" => kind, "mode" => mode, "required" => required} ->
            with :ok <- exact_fields(entry, ~w(path kind mode required), path),
                 true <-
                   relative?(output) or
                     {:error, "#{path}.path: expected a normalized relative path"},
                 true <-
                   kind in ~w(file directory symlink) or
                     {:error, "#{path}.kind: unsupported entry kind"},
                 true <-
                   (is_integer(mode) and mode >= 0 and mode <= 0o777) or
                     {:error, "#{path}.mode: expected 0..511"},
                 true <- is_boolean(required) or {:error, "#{path}.required: expected a boolean"},
                 :ok <-
                   ensure(
                     not MapSet.member?(seen, output),
                     "#{path}.path: duplicate output"
                   ) do
              {:cont, {:ok, MapSet.put(seen, output)}}
            else
              {:error, _} = error -> {:halt, error}
            end

          _ ->
            {:halt, {:error, "#{path}: expected path, kind, mode and required"}}
        end
      end)

    case result do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp outputs(_), do: {:error, "$.outputs: expected a non-empty list"}

  defp native_inputs(value) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {entry, index}, :ok ->
      path = "$.native_inputs[#{index}]"

      case entry do
        %{"name" => input_name, "build_identity" => identity} ->
          with :ok <- exact_fields(entry, ~w(name build_identity), path),
               {:ok, _} <- name(input_name, "#{path}.name"),
               true <-
                 digest?(identity) or
                   {:error, "#{path}.build_identity: expected full lowercase SHA-256"} do
            {:cont, :ok}
          else
            {:error, _} = error -> {:halt, error}
          end

        _ ->
          {:halt, {:error, "#{path}: expected name and build_identity"}}
      end
    end)
  end

  defp native_inputs(_), do: {:error, "$.native_inputs: expected a list"}

  defp retrieval(%{"sources" => sources} = retrieval) do
    with :ok <- exact_fields(retrieval, ~w(sources), "$.retrieval") do
      retrieval_sources(sources)
    end
  end

  defp retrieval(_), do: {:error, "$.retrieval: expected sources"}

  defp retrieval_sources(sources) when is_list(sources) and length(sources) <= 8 do
    results = Enum.with_index(sources) |> Enum.map(&retrieval_source/1)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        names = Enum.map(sources, & &1["name"])

        if names == Enum.uniq(names),
          do: :ok,
          else: {:error, "$.retrieval.sources: duplicate source names are not allowed"}

      {:error, _} = error ->
        error
    end
  end

  defp retrieval_sources(sources) when is_list(sources),
    do: {:error, "$.retrieval.sources: at most 8 sources are allowed"}

  defp retrieval_sources(_), do: {:error, "$.retrieval.sources: expected a list"}

  defp retrieval_source({%{"name" => source_name, "url" => url}, index} = source) do
    path = "$.retrieval.sources[#{index}]"

    with :ok <- exact_fields(elem(source, 0), ~w(name url), path),
         {:ok, _} <- name(source_name, "#{path}.name") do
      retrieval_url(url, "#{path}.url")
    end
  end

  defp retrieval_source({_, index}),
    do: {:error, "$.retrieval.sources[#{index}]: expected name and url"}

  defp retrieval_url(url, path) when is_binary(url) do
    expanded =
      Enum.reduce(
        ~w(package profile target build_identity),
        url,
        &String.replace(
          &2,
          "{#{&1}}",
          if(&1 == "build_identity", do: String.duplicate("0", 64), else: "cell")
        )
      )

    uri = URI.parse(expanded)

    cond do
      not String.contains?(url, "{build_identity}") ->
        {:error, "#{path}: URL must include {build_identity}"}

      String.contains?(expanded, ["{", "}"]) ->
        {:error, "#{path}: URL contains an unknown template variable"}

      uri.scheme != "https" or not is_binary(uri.host) or uri.host == "" ->
        {:error, "#{path}: expected an HTTPS URL template"}

      not is_nil(uri.userinfo) or not is_nil(uri.query) or not is_nil(uri.fragment) ->
        {:error, "#{path}: credentials, query strings and fragments are forbidden"}

      uri.path in [nil, ""] ->
        {:error, "#{path}: URL template must contain a path"}

      true ->
        :ok
    end
  end

  defp retrieval_url(_, path), do: {:error, "#{path}: expected a string"}

  defp paths(value, path, empty?) when is_list(value) do
    cond do
      not empty? and value == [] -> {:error, "#{path}: expected at least one path"}
      not Enum.all?(value, &relative?/1) -> {:error, "#{path}: expected normalized relative paths"}
      Enum.uniq(value) != value -> {:error, "#{path}: duplicate paths are not allowed"}
      true -> :ok
    end
  end

  defp paths(_, path, _), do: {:error, "#{path}: expected a list of paths"}

  defp strings(value, path) when is_list(value) do
    cond do
      not Enum.all?(value, &(is_binary(&1) and &1 != "" and String.valid?(&1))) ->
        {:error, "#{path}: expected non-empty UTF-8 strings"}

      Enum.uniq(value) != value ->
        {:error, "#{path}: duplicate values are not allowed"}

      true ->
        :ok
    end
  end

  defp strings(_, path), do: {:error, "#{path}: expected a list of strings"}

  defp identity_value(value, path) do
    case CanonicalJSON.encode(value) do
      {:ok, _} -> :ok
      {:error, message} -> {:error, String.replace_prefix(message, "$", path)}
    end
  end

  defp safe_values(value, path) when is_map(value) do
    Enum.reduce_while(value, :ok, fn {key, item}, :ok ->
      if Regex.match?(@forbidden_key, key) do
        {:halt, {:error, "#{path}.#{key}: forbidden descriptor field"}}
      else
        case safe_values(item, "#{path}.#{key}") do
          :ok -> {:cont, :ok}
          {:error, _} = error -> {:halt, error}
        end
      end
    end)
  end

  defp safe_values(value, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {item, index}, :ok ->
      case safe_values(item, "#{path}[#{index}]") do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp safe_values(value, path) when is_binary(value) do
    if local_absolute?(value),
      do: {:error, "#{path}: machine-specific absolute paths are forbidden"},
      else: :ok
  end

  defp safe_values(_, _), do: :ok

  defp normalize(map) do
    normalized =
      map
      |> put_in(["targets"], Enum.sort_by(map["targets"], & &1["name"]))
      |> put_in(["sources", "first_party"], Enum.sort(map["sources"]["first_party"]))
      |> put_in(["sources", "upstream"], Enum.sort_by(map["sources"]["upstream"], & &1["name"]))
      |> put_in(["toolchain", "inputs"], Enum.sort(map["toolchain"]["inputs"]))
      |> put_in(["build", "features"], Enum.sort(map["build"]["features"]))
      |> put_in(["qualification", "features"], Enum.sort(map["qualification"]["features"]))
      |> put_in(["outputs"], Enum.sort_by(map["outputs"], & &1["path"]))
      |> put_in(["external_libraries"], Enum.sort(map["external_libraries"]))
      |> put_in(["legal"], Enum.sort(map["legal"]))
      |> put_in(["native_inputs"], Enum.sort_by(map["native_inputs"], & &1["name"]))

    {:ok, normalized}
  end

  defp relative?(path) when is_binary(path) and path != "" do
    parts = String.split(path, "/", trim: false)

    String.valid?(path) and Path.type(path) == :relative and Path.expand(path, "/") != path and
      Enum.all?(parts, &(&1 not in ["", ".", ".."])) and not String.contains?(path, <<0>>)
  end

  defp relative?(_), do: false

  defp immutable_url?(url), do: is_binary(url) and String.starts_with?(url, "https://")

  defp immutable_revision?(revision) when is_binary(revision) do
    Regex.match?(~r/^[0-9a-f]{40}$/, revision) or
      Regex.match?(~r/^v?\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/, revision)
  end

  defp immutable_revision?(_), do: false
  defp digest?(value), do: is_binary(value) and Regex.match?(@digest, value)

  defp local_absolute?(value) do
    String.starts_with?(value, "/") or Regex.match?(~r/^[A-Za-z]:[\\\/]/, value)
  end

  defp ensure(true, _), do: :ok
  defp ensure(false, message), do: {:error, message}
end
