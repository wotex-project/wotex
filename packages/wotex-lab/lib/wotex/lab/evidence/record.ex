defmodule Wotex.Lab.Evidence.Record do
  @moduledoc """
  A schema-versioned run record: the unit of Lab evidence.

  Every record names the scenario, revision and attempt it belongs to, the
  source-tree and lock digests it ran against, the exact dependency versions
  with their archive digests, fixture digests, seed, toolchain, budgets,
  input references, assertions, outcomes, durations and cleanup result. A
  dependency without archive evidence carries `archive: :missing`; the record
  never synthesizes an archive digest from a source checkout, and a
  dependency that omits the field entirely is rejected so the absence is
  always stated rather than implied.

  Public evidence carries no secrets, callbacks or executable paths: every
  value is scanned, functions, pids, ports and references are refused, and
  binaries that look like filesystem paths or credential material are refused
  as well. `to_map/1` produces a JSON-compatible map with string keys and
  `encode/1` produces canonical bytes whose SHA-256 is `digest/1`, so two
  records with the same content have the same digest. `from_map/1` reads a
  record back with the same validation.
  """

  alias Wotex.JSON
  alias Wotex.Lab.Error

  @schema_version "1.0.0"
  @digest ~r/\Asha256:[0-9a-f]{64}\z/
  @secret ~r/(?i)(bearer\s|password\s*[=:]|passwd|secret\s*[=:]|token\s*[=:]|-----BEGIN)/
  @path ~r/\A(?:\/|~\/|\.\.?\/|[A-Za-z]:\\)/
  @statuses ~w(pass fail unsupported not_run infrastructure_error)a
  @max_text_bytes 512
  @max_collection 1_024

  @type status :: :pass | :fail | :unsupported | :not_run | :infrastructure_error

  @type dependency :: %{
          required(:name) => String.t(),
          required(:version) => String.t(),
          required(:archive) => String.t() | :missing
        }

  @type t :: %__MODULE__{
          schema_version: String.t(),
          scenario_id: String.t(),
          revision: String.t(),
          attempt: pos_integer(),
          source_tree_digest: String.t(),
          lock_digest: String.t(),
          dependencies: [dependency()],
          fixtures: %{String.t() => String.t()},
          seed: integer(),
          toolchain: %{
            elixir: String.t(),
            otp: String.t(),
            backend: String.t(),
            platform: String.t()
          },
          budgets: %{atom() => non_neg_integer()},
          inputs: [String.t()],
          assertions: [%{id: String.t(), status: status()}],
          outcomes: %{atom() => atom() | String.t() | number() | boolean()},
          durations: %{atom() => non_neg_integer()},
          cleanup: %{status: :ok | :failed, details: map()}
        }

  @enforce_keys [
    :scenario_id,
    :revision,
    :attempt,
    :source_tree_digest,
    :lock_digest,
    :dependencies,
    :fixtures,
    :seed,
    :toolchain,
    :budgets,
    :inputs,
    :assertions,
    :outcomes,
    :durations,
    :cleanup
  ]

  defstruct [{:schema_version, @schema_version} | @enforce_keys]

  @doc "The record schema version written by this module."
  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @doc "Builds a validated record from keyword or map fields."
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, Error.t()}
  def new(fields) when is_list(fields), do: fields |> Map.new() |> new()

  def new(fields) when is_map(fields) do
    with :ok <- required(fields),
         :ok <- text(fields, :scenario_id),
         :ok <- text(fields, :revision),
         :ok <- positive(fields, :attempt),
         :ok <- digest(fields, :source_tree_digest),
         :ok <- digest(fields, :lock_digest),
         :ok <- dependencies(fields.dependencies),
         :ok <- fixtures(fields.fixtures),
         :ok <- check(is_integer(fields.seed), :invalid_seed, "/seed", "seed must be an integer"),
         :ok <- toolchain(fields.toolchain),
         :ok <- counts(fields.budgets, :invalid_budgets, "/budgets"),
         :ok <- inputs(fields.inputs),
         :ok <- assertions(fields.assertions),
         :ok <- outcomes(fields.outcomes),
         :ok <- counts(fields.durations, :invalid_durations, "/durations"),
         :ok <- cleanup(fields.cleanup),
         :ok <- public(fields, "") do
      {:ok, struct!(__MODULE__, Map.take(fields, @enforce_keys))}
    end
  end

  def new(_),
    do: {:error, Error.new(:invalid_record, :construction, "record fields must be a map")}

  @doc "Reads a record back from its string-keyed map form."
  @spec from_map(map()) :: {:ok, t()} | {:error, Error.t()}
  def from_map(%{"schema_version" => @schema_version} = map) do
    fields = %{
      scenario_id: map["scenario_id"],
      revision: map["revision"],
      attempt: map["attempt"],
      source_tree_digest: map["source_tree_digest"],
      lock_digest: map["lock_digest"],
      dependencies: Enum.map(list(map["dependencies"]), &dependency_from_map/1),
      fixtures: map["fixtures"] || %{},
      seed: map["seed"],
      toolchain: atom_keys(map["toolchain"], [:elixir, :otp, :backend, :platform]),
      budgets: counts_from_map(map["budgets"]),
      inputs: list(map["inputs"]),
      assertions: Enum.map(list(map["assertions"]), &assertion_from_map/1),
      outcomes: outcomes_from_map(map["outcomes"]),
      durations: counts_from_map(map["durations"]),
      cleanup: cleanup_from_map(map["cleanup"])
    }

    new(fields)
  end

  def from_map(%{"schema_version" => other}) when is_binary(other) do
    {:error,
     Error.new(:unsupported_schema_version, :construction, "record schema version is not readable",
       path: "/schema_version",
       details: %{schema_version: other, supported: [@schema_version]}
     )}
  end

  def from_map(_),
    do:
      {:error, Error.new(:invalid_record, :construction, "record map must name its schema version")}

  @doc "Returns the JSON-compatible, string-keyed form of a record."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = record) do
    %{
      "schema_version" => record.schema_version,
      "scenario_id" => record.scenario_id,
      "revision" => record.revision,
      "attempt" => record.attempt,
      "source_tree_digest" => record.source_tree_digest,
      "lock_digest" => record.lock_digest,
      "dependencies" =>
        Enum.map(record.dependencies, fn dependency ->
          %{
            "name" => dependency.name,
            "version" => dependency.version,
            "archive" => plain(dependency.archive)
          }
        end),
      "fixtures" => record.fixtures,
      "seed" => record.seed,
      "toolchain" => string_keys(record.toolchain),
      "budgets" => string_keys(record.budgets),
      "inputs" => record.inputs,
      "assertions" =>
        Enum.map(record.assertions, &%{"id" => &1.id, "status" => Atom.to_string(&1.status)}),
      "outcomes" => record.outcomes |> string_keys() |> Map.new(fn {k, v} -> {k, plain(v)} end),
      "durations" => string_keys(record.durations),
      "cleanup" => %{
        "status" => Atom.to_string(record.cleanup.status),
        "details" =>
          record.cleanup.details |> string_keys() |> Map.new(fn {k, v} -> {k, plain(v)} end)
      }
    }
  end

  @doc "Encodes a record canonically: sorted keys, no insignificant whitespace."
  @spec encode(t()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(%__MODULE__{} = record) do
    case JSON.encode(to_map(record)) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, error} -> {:error, Error.new(:invalid_record, :encode, error.message)}
    end
  end

  @doc "The SHA-256 of the canonical encoding, as `sha256:<hex>`."
  @spec digest(t()) :: {:ok, String.t()} | {:error, Error.t()}
  def digest(%__MODULE__{} = record) do
    with {:ok, bytes} <- encode(record) do
      {:ok, "sha256:" <> (:crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower))}
    end
  end

  defp required(fields) do
    case Enum.reject(@enforce_keys, &Map.has_key?(fields, &1)) do
      [] ->
        :ok

      missing ->
        {:error,
         Error.new(:missing_field, :construction, "record is missing required fields",
           details: %{missing: missing}
         )}
    end
  end

  defp text(fields, key) do
    value = Map.get(fields, key)

    check(
      is_binary(value) and value != "" and byte_size(value) <= @max_text_bytes,
      :invalid_text,
      "/#{key}",
      "#{key} must be a non-empty string of at most #{@max_text_bytes} bytes"
    )
  end

  defp positive(fields, key) do
    value = Map.get(fields, key)
    check(is_integer(value) and value > 0, :invalid_attempt, "/#{key}", "#{key} must be positive")
  end

  defp digest(fields, key) do
    value = Map.get(fields, key)

    check(
      is_binary(value) and Regex.match?(@digest, value),
      :invalid_digest,
      "/#{key}",
      "#{key} must be sha256:<64 lowercase hex>"
    )
  end

  defp dependencies(list) when is_list(list) and length(list) <= @max_collection do
    list
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {dependency, index}, :ok ->
      case dependency(dependency, "/dependencies/#{index}") do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp dependencies(_),
    do:
      {:error,
       Error.new(:invalid_dependencies, :construction, "dependencies must be a bounded list",
         path: "/dependencies"
       )}

  defp dependency(%{name: name, version: version} = dependency, path)
       when is_binary(name) and is_binary(version) do
    case Map.fetch(dependency, :archive) do
      {:ok, :missing} ->
        :ok

      {:ok, archive} when is_binary(archive) ->
        check(
          Regex.match?(@digest, archive),
          :invalid_digest,
          path <> "/archive",
          "archive must be a sha256 digest"
        )

      _ ->
        {:error,
         Error.new(
           :archive_evidence_unstated,
           :construction,
           "dependency must state its archive digest or :missing",
           path: path <> "/archive"
         )}
    end
  end

  defp dependency(_, path),
    do:
      {:error,
       Error.new(:invalid_dependency, :construction, "dependency needs name and version",
         path: path
       )}

  defp fixtures(map) when is_map(map) and map_size(map) <= @max_collection do
    Enum.reduce_while(map, :ok, fn {name, value}, :ok ->
      if is_binary(name) and is_binary(value) and Regex.match?(@digest, value),
        do: {:cont, :ok},
        else:
          {:halt,
           {:error,
            Error.new(:invalid_digest, :construction, "fixture digests must be sha256",
              path: "/fixtures"
            )}}
    end)
  end

  defp fixtures(_),
    do:
      {:error,
       Error.new(:invalid_fixtures, :construction, "fixtures must be a bounded map",
         path: "/fixtures"
       )}

  defp toolchain(%{elixir: elixir, otp: otp, backend: backend, platform: platform})
       when is_binary(elixir) and is_binary(otp) and is_binary(backend) and is_binary(platform),
       do: :ok

  defp toolchain(_),
    do:
      {:error,
       Error.new(
         :invalid_toolchain,
         :construction,
         "toolchain needs elixir, otp, backend and platform strings",
         path: "/toolchain"
       )}

  defp counts(map, code, path) when is_map(map) and map_size(map) <= @max_collection do
    if Enum.all?(map, fn {key, value} -> is_atom(key) and is_integer(value) and value >= 0 end),
      do: :ok,
      else:
        {:error,
         Error.new(code, :construction, "values must be non-negative integers keyed by atoms",
           path: path
         )}
  end

  defp counts(_, code, path),
    do: {:error, Error.new(code, :construction, "must be a bounded map", path: path)}

  defp inputs(list) when is_list(list) and length(list) <= @max_collection do
    if Enum.all?(list, &(is_binary(&1) and &1 != "" and byte_size(&1) <= @max_text_bytes)),
      do: :ok,
      else:
        {:error,
         Error.new(:invalid_inputs, :construction, "inputs must be bounded reference strings",
           path: "/inputs"
         )}
  end

  defp inputs(_),
    do:
      {:error,
       Error.new(:invalid_inputs, :construction, "inputs must be a bounded list", path: "/inputs")}

  defp assertions(list) when is_list(list) and length(list) <= @max_collection do
    if Enum.all?(
         list,
         &match?(%{id: id, status: status} when is_binary(id) and status in @statuses, &1)
       ),
       do: :ok,
       else:
         {:error,
          Error.new(:invalid_assertions, :construction, "assertions need an id and a runner status",
            path: "/assertions"
          )}
  end

  defp assertions(_),
    do:
      {:error,
       Error.new(:invalid_assertions, :construction, "assertions must be a bounded list",
         path: "/assertions"
       )}

  defp outcomes(map) when is_map(map) and map_size(map) <= @max_collection do
    if Enum.all?(map, fn {key, value} -> is_atom(key) and scalar?(value) end),
      do: :ok,
      else:
        {:error,
         Error.new(:invalid_outcomes, :construction, "outcomes must be scalars keyed by atoms",
           path: "/outcomes"
         )}
  end

  defp outcomes(_),
    do:
      {:error,
       Error.new(:invalid_outcomes, :construction, "outcomes must be a bounded map",
         path: "/outcomes"
       )}

  defp cleanup(%{status: status, details: details})
       when status in [:ok, :failed] and is_map(details),
       do: :ok

  defp cleanup(_),
    do:
      {:error,
       Error.new(:invalid_cleanup, :construction, "cleanup needs status :ok or :failed and details",
         path: "/cleanup"
       )}

  # Public evidence must not carry callbacks, process identities, paths or secrets.
  defp public(value, path)
       when is_function(value) or is_pid(value) or is_port(value) or is_reference(value),
       do:
         {:error,
          Error.new(
            :not_public_evidence,
            :construction,
            "callbacks and process identities cannot be evidence",
            path: path
          )}

  defp public(value, path) when is_binary(value) do
    cond do
      Regex.match?(@path, value) ->
        {:error,
         Error.new(:not_public_evidence, :construction, "filesystem paths cannot be evidence",
           path: path
         )}

      Regex.match?(@secret, value) ->
        {:error,
         Error.new(:not_public_evidence, :construction, "credential material cannot be evidence",
           path: path
         )}

      true ->
        :ok
    end
  end

  defp public(%_{} = struct, path),
    do:
      {:error,
       Error.new(:not_public_evidence, :construction, "structs cannot be evidence",
         path: path,
         details: %{struct: struct.__struct__}
       )}

  defp public(map, path) when is_map(map) do
    Enum.reduce_while(map, :ok, fn {key, value}, :ok ->
      case public(value, path <> "/" <> to_string(key)) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp public(list, path) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {value, index}, :ok ->
      case public(value, path <> "/#{index}") do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp public(_, _), do: :ok

  defp scalar?(value), do: is_atom(value) or is_binary(value) or is_number(value)

  defp check(true, _, _, _), do: :ok

  defp check(false, code, path, message),
    do: {:error, Error.new(code, :construction, message, path: path)}

  defp plain(value) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: Atom.to_string(value)

  defp plain(value), do: value

  defp string_keys(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp list(value) when is_list(value), do: value
  defp list(_), do: []

  defp atom_keys(map, keys) when is_map(map),
    do: Map.new(keys, fn key -> {key, Map.get(map, Atom.to_string(key))} end)

  defp atom_keys(_, _), do: %{}

  defp counts_from_map(map) when is_map(map) and map_size(map) <= @max_collection,
    do: Map.new(map, fn {key, value} -> {existing_atom(key), value} end)

  defp counts_from_map(_), do: :invalid

  defp outcomes_from_map(map) when is_map(map) and map_size(map) <= @max_collection,
    do: Map.new(map, fn {key, value} -> {existing_atom(key), value} end)

  defp outcomes_from_map(_), do: :invalid

  defp dependency_from_map(%{"name" => name, "version" => version} = map) do
    case Map.fetch(map, "archive") do
      {:ok, "missing"} -> %{name: name, version: version, archive: :missing}
      {:ok, archive} -> %{name: name, version: version, archive: archive}
      :error -> %{name: name, version: version}
    end
  end

  defp dependency_from_map(other), do: other

  defp assertion_from_map(%{"id" => id, "status" => status}) when is_binary(status),
    do: %{id: id, status: Enum.find(@statuses, :invalid, &(Atom.to_string(&1) == status))}

  defp assertion_from_map(other), do: other

  defp cleanup_from_map(%{"status" => status, "details" => details}) when is_map(details),
    do: %{
      status: Enum.find([:ok, :failed], :invalid, &(Atom.to_string(&1) == status)),
      details: details
    }

  defp cleanup_from_map(_), do: :invalid

  # Keys are read back only as atoms that already exist; unknown keys stay
  # strings and fail validation.
  defp existing_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end
end
