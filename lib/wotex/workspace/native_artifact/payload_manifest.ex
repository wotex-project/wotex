defmodule Wotex.Workspace.NativeArtifact.PayloadManifest do
  @moduledoc """
  Deterministic payload manifests for verified native artifact outputs.

  Payload identity is independent of transport bytes and build identity. It is
  the full SHA-256 of the canonical entry set, including normalized paths,
  kinds, modes, sizes, link targets and regular-file digests.
  """

  import Bitwise

  alias Wotex.Workspace.NativeArtifact.CanonicalJSON
  alias Wotex.Workspace.NativeArtifact.Descriptor
  alias Wotex.Workspace.NativeArtifact.Identity

  @schema "wotex.native-payload-manifest@1"
  @payload_schema "wotex.native-payload@1"
  @artifact_format "wotex.native-artifact@1"
  @digest ~r/^[0-9a-f]{64}$/
  @fields ~w(schema artifact_format package profile target build_identity payload_identity required optional entries)
  @required Enum.sort(@fields -- ["optional"])

  @type entry :: %{
          String.t() => String.t() | non_neg_integer() | nil
        }

  @type t :: %__MODULE__{
          package: String.t(),
          profile: String.t(),
          target: String.t(),
          build_identity: String.t(),
          payload_identity: String.t(),
          entries: [entry()],
          optional: map()
        }

  @enforce_keys [
    :package,
    :profile,
    :target,
    :build_identity,
    :payload_identity,
    :entries
  ]
  defstruct package: nil,
            profile: nil,
            target: nil,
            build_identity: nil,
            payload_identity: nil,
            entries: nil,
            optional: %{}

  @doc "The accepted payload manifest schema."
  @spec schema() :: String.t()
  def schema, do: @schema

  @doc "Builds a manifest by walking only descriptor-declared output roots."
  @spec build(Descriptor.t(), String.t(), String.t(), Path.t()) ::
          {:ok, t()} | {:error, String.t()}
  def build(%Descriptor{} = descriptor, target, build_identity, root) do
    with :ok <- full_digest(build_identity, "build identity"),
         :ok <- supported_target(descriptor, target),
         :ok <- ordinary_directory(root),
         {:ok, entries} <- declared_entries(descriptor.raw["outputs"], root),
         {:ok, payload_identity} <- payload_identity(entries) do
      {:ok,
       %__MODULE__{
         package: descriptor.package,
         profile: descriptor.profile,
         target: target,
         build_identity: build_identity,
         payload_identity: payload_identity,
         entries: entries
       }}
    end
  end

  @doc "Decodes and validates a bounded manifest document."
  @spec decode(binary(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def decode(bytes, opts \\ []) when is_binary(bytes) do
    max_bytes = Keyword.get(opts, :max_bytes, 1_048_576)
    max_depth = Keyword.get(opts, :max_depth, 32)
    max_nodes = Keyword.get(opts, :max_nodes, 100_000)

    if byte_size(bytes) > max_bytes do
      {:error, "payload manifest exceeds #{max_bytes} bytes"}
    else
      with {:ok, map} <- decode_json(bytes),
           :ok <- bounded_shape(map, max_depth, max_nodes) do
        from_map(map)
      end
    end
  end

  @doc "Validates a decoded payload manifest."
  @spec from_map(term()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    with :ok <- exact_fields(map),
         :ok <- exact_value(map, "schema", @schema),
         :ok <- exact_value(map, "artifact_format", @artifact_format),
         :ok <- required_fields(map["required"]),
         :ok <- identity_value(map["optional"], "$.optional"),
         :ok <- nonempty_string(map["package"], "$.package"),
         :ok <- nonempty_string(map["profile"], "$.profile"),
         :ok <- nonempty_string(map["target"], "$.target"),
         :ok <- full_digest(map["build_identity"], "$.build_identity"),
         :ok <- full_digest(map["payload_identity"], "$.payload_identity"),
         {:ok, entries} <- entries(map["entries"]),
         {:ok, actual_identity} <- payload_identity(entries),
         :ok <- identity_matches(map["payload_identity"], actual_identity) do
      {:ok,
       %__MODULE__{
         package: map["package"],
         profile: map["profile"],
         target: map["target"],
         build_identity: map["build_identity"],
         payload_identity: actual_identity,
         entries: entries,
         optional: map["optional"]
       }}
    end
  end

  def from_map(_), do: {:error, "$: payload manifest must be a JSON object"}

  @doc "Returns the canonical manifest map used on disk."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = manifest) do
    %{
      "schema" => @schema,
      "artifact_format" => @artifact_format,
      "package" => manifest.package,
      "profile" => manifest.profile,
      "target" => manifest.target,
      "build_identity" => manifest.build_identity,
      "payload_identity" => manifest.payload_identity,
      "required" => @required,
      "optional" => manifest.optional,
      "entries" => manifest.entries
    }
  end

  @doc "Encodes a validated manifest as canonical JSON."
  @spec encode(t()) :: {:ok, binary()} | {:error, String.t()}
  def encode(%__MODULE__{} = manifest), do: CanonicalJSON.encode(to_map(manifest))

  @doc "Computes the payload identity for normalized manifest entries."
  @spec payload_identity([entry()]) :: {:ok, String.t()} | {:error, String.t()}
  def payload_identity(entries) do
    with {:ok, canonical} <-
           CanonicalJSON.encode(%{"schema" => @payload_schema, "entries" => entries}) do
      {:ok, Identity.sha256(canonical)}
    end
  end

  @doc "Validates one normalized artifact-relative path."
  @spec validate_path(term()) :: :ok | {:error, String.t()}
  def validate_path(path), do: normalized_path(path)

  @doc "Resolves a relative link target to its normalized artifact-root path."
  @spec normalize_link_target(String.t(), term()) :: {:ok, String.t()} | {:error, String.t()}
  def normalize_link_target(link_path, target), do: normalized_link_target(link_path, target)

  defp declared_entries(outputs, root) do
    outputs
    |> Enum.reduce_while({:ok, []}, fn output, {:ok, entries} ->
      case collect_declared_output(root, output) do
        {:ok, additions} ->
          {:cont, {:ok, additions ++ entries}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> normalize_entries()
  end

  defp collect_declared_output(root, output) do
    absolute = Path.join(root, output["path"])

    case File.lstat(absolute) do
      {:error, :enoent} ->
        if output["required"],
          do: {:error, "#{output["path"]}: #{:file.format_error(:enoent)}"},
          else: {:ok, []}

      {:error, reason} ->
        {:error, "#{output["path"]}: #{:file.format_error(reason)}"}

      {:ok, _} ->
        with {:ok, entries} <- collect(absolute, output["path"]),
             root_entry <- Enum.find(entries, &(&1["path"] == output["path"])),
             :ok <- declared_root_matches(root_entry, output) do
          {:ok, entries}
        end
    end
  end

  defp declared_root_matches(entry, output) do
    cond do
      entry["kind"] != output["kind"] ->
        {:error, "#{output["path"]}: expected #{output["kind"]}, found #{entry["kind"]}"}

      entry["mode"] != output["mode"] ->
        {:error, "#{output["path"]}: expected mode #{output["mode"]}, found #{entry["mode"]}"}

      true ->
        :ok
    end
  end

  defp collect(absolute, relative) do
    with :ok <- normalized_path(relative),
         {:ok, stat} <- lstat(absolute, relative) do
      case stat.type do
        :regular -> regular_entry(absolute, relative, stat)
        :directory -> directory_entries(absolute, relative, stat)
        :symlink -> symlink_entry(absolute, relative, stat)
        type -> {:error, "#{relative}: output kind #{type} is not supported"}
      end
    end
  end

  defp regular_entry(absolute, relative, stat) do
    case hash_file(absolute) do
      {:ok, digest, size} ->
        {:ok,
         [
           %{
             "path" => relative,
             "kind" => "file",
             "mode" => band(stat.mode, 0o777),
             "size" => size,
             "sha256" => digest,
             "link_target" => nil
           }
         ]}

      {:error, reason} ->
        {:error, "#{relative}: #{:file.format_error(reason)}"}
    end
  end

  defp directory_entries(absolute, relative, stat) do
    case File.ls(absolute) do
      {:ok, names} ->
        own = %{
          "path" => relative,
          "kind" => "directory",
          "mode" => band(stat.mode, 0o777),
          "size" => 0,
          "sha256" => nil,
          "link_target" => nil
        }

        names
        |> Enum.sort()
        |> Enum.reduce_while({:ok, [own]}, fn name, {:ok, entries} ->
          child_relative = Path.join(relative, name)

          case collect(Path.join(absolute, name), child_relative) do
            {:ok, additions} -> {:cont, {:ok, additions ++ entries}}
            {:error, _} = error -> {:halt, error}
          end
        end)

      {:error, reason} ->
        {:error, "#{relative}: #{:file.format_error(reason)}"}
    end
  end

  defp symlink_entry(absolute, relative, stat) do
    with {:ok, target} <- File.read_link(absolute),
         {:ok, normalized_target} <- normalized_link_target(relative, target) do
      {:ok,
       [
         %{
           "path" => relative,
           "kind" => "symlink",
           "mode" => band(stat.mode, 0o777),
           "size" => 0,
           "sha256" => nil,
           "link_target" => normalized_target
         }
       ]}
    else
      {:error, reason} when is_atom(reason) ->
        {:error, "#{relative}: #{:file.format_error(reason)}"}

      {:error, _} = error ->
        error
    end
  end

  defp normalize_entries({:error, _} = error), do: error

  defp normalize_entries({:ok, entries}) do
    sorted = Enum.sort_by(entries, & &1["path"])
    paths = Enum.map(sorted, & &1["path"])

    if Enum.uniq(paths) == paths,
      do: {:ok, sorted},
      else: {:error, "descriptor output roots overlap after normalization"}
  end

  defp entries(value) when is_list(value) do
    result =
      value
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {entry, index}, {:ok, entries} ->
        case entry(entry, index) do
          {:ok, parsed} -> {:cont, {:ok, [parsed | entries]}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case result do
      {:ok, parsed} -> normalize_entries({:ok, parsed})
      {:error, _} = error -> error
    end
  end

  defp entries(_), do: {:error, "$.entries: expected a list"}

  defp entry(entry, index) when is_map(entry) do
    path = "$.entries[#{index}]"

    with [] <- Map.keys(entry) -- ~w(path kind mode size sha256 link_target),
         [] <- ~w(path kind mode size sha256 link_target) -- Map.keys(entry),
         :ok <- normalized_path(entry["path"]),
         :ok <- entry_kind(entry["kind"], path),
         :ok <- mode(entry["mode"], path),
         :ok <- entry_values(entry, path) do
      {:ok, Map.take(entry, ~w(path kind mode size sha256 link_target))}
    else
      [_ | _] ->
        {:error, "#{path}: fields must be exactly path, kind, mode, size, sha256 and link_target"}

      {:error, _} = error ->
        error
    end
  end

  defp entry(_, index), do: {:error, "$.entries[#{index}]: expected an object"}

  defp entry_kind(kind, _) when kind in ~w(file directory symlink), do: :ok
  defp entry_kind(_, path), do: {:error, "#{path}.kind: unsupported entry kind"}

  defp entry_values(
         %{"kind" => "file", "size" => size, "sha256" => digest, "link_target" => nil},
         path
       )
       when is_integer(size) and size >= 0 do
    full_digest(digest, "#{path}.sha256")
  end

  defp entry_values(
         %{"kind" => kind, "size" => 0, "sha256" => nil, "link_target" => nil},
         _
       )
       when kind == "directory",
       do: :ok

  defp entry_values(
         %{
           "kind" => "symlink",
           "size" => 0,
           "sha256" => nil,
           "link_target" => target
         },
         path
       ) do
    with :ok <- nonempty_string(target, "#{path}.link_target") do
      normalized_path(target)
    end
  end

  defp entry_values(_, path), do: {:error, "#{path}: size, digest or link target contradicts kind"}

  defp mode(value, _) when is_integer(value) and value >= 0 and value <= 0o777, do: :ok
  defp mode(_, path), do: {:error, "#{path}.mode: expected 0..511"}

  defp exact_fields(map) do
    missing = @fields -- Map.keys(map)
    unknown = Map.keys(map) -- @fields

    cond do
      missing != [] ->
        {:error, "$: missing required fields: #{Enum.join(Enum.sort(missing), ", ")}"}

      unknown != [] ->
        {:error, "$: unknown fields: #{Enum.join(Enum.sort(unknown), ", ")}"}

      true ->
        :ok
    end
  end

  defp required_fields(value) when is_list(value) do
    cond do
      not Enum.all?(value, &is_binary/1) ->
        {:error, "$.required: expected field names"}

      Enum.sort(value) != @required ->
        unknown = value -- @required
        missing = @required -- value

        {:error,
         "$.required: unknown required fields #{inspect(Enum.sort(unknown))}; missing #{inspect(Enum.sort(missing))}"}

      true ->
        :ok
    end
  end

  defp required_fields(_), do: {:error, "$.required: expected a list"}

  defp identity_matches(expected, actual) when expected == actual, do: :ok

  defp identity_matches(expected, actual),
    do: {:error, "$.payload_identity: expected #{expected}, computed #{actual}"}

  defp exact_value(map, key, expected) do
    if map[key] == expected,
      do: :ok,
      else: {:error, "$.#{key}: expected #{inspect(expected)}, got #{inspect(map[key])}"}
  end

  defp supported_target(descriptor, target) do
    case Descriptor.target(descriptor, target) do
      {:ok, %{status: :supported}} -> :ok
      {:ok, %{status: :unsupported, reason: reason}} -> {:error, "target is unsupported: #{reason}"}
      {:error, _} = error -> error
    end
  end

  defp ordinary_directory(root) do
    if not is_binary(root) or Path.type(root) != :absolute do
      {:error, "payload root must be absolute"}
    else
      case File.lstat(root) do
        {:ok, %{type: :directory}} -> :ok
        {:ok, %{type: type}} -> {:error, "payload root must be a directory, got #{type}"}
        {:error, reason} -> {:error, "payload root: #{:file.format_error(reason)}"}
      end
    end
  end

  defp lstat(absolute, relative) do
    case File.lstat(absolute) do
      {:ok, stat} -> {:ok, stat}
      {:error, reason} -> {:error, "#{relative}: #{:file.format_error(reason)}"}
    end
  end

  defp hash_file(path) do
    with {:ok, io} <- File.open(path, [:read, :binary]) do
      try do
        hash_io(io, :crypto.hash_init(:sha256), 0)
      after
        File.close(io)
      end
    end
  end

  defp hash_io(io, context, size) do
    case IO.binread(io, 65_536) do
      :eof ->
        digest = :crypto.hash_final(context)
        {:ok, Base.encode16(digest, case: :lower), size}

      {:error, reason} ->
        {:error, reason}

      bytes ->
        hash_io(io, :crypto.hash_update(context, bytes), size + byte_size(bytes))
    end
  end

  defp normalized_path(path) when is_binary(path) and path != "" do
    components = String.split(path, "/", trim: false)

    if String.valid?(path) and Path.type(path) == :relative and
         Enum.all?(components, &(&1 not in ["", ".", ".."])) and not String.contains?(path, <<0>>) do
      :ok
    else
      {:error, "#{inspect(path)}: expected a normalized relative UTF-8 path"}
    end
  end

  defp normalized_path(path),
    do: {:error, "#{inspect(path)}: expected a normalized relative UTF-8 path"}

  defp normalized_link_target(link_path, target) when is_binary(target) do
    if target != "" and String.valid?(target) and Path.type(target) == :relative and
         not String.contains?(target, <<0>>) do
      directory = Path.dirname(link_path)
      directory_components = String.split(directory, "/", trim: true)
      initial = Enum.reverse(directory_components)
      components = String.split(target, "/", trim: false)

      result =
        Enum.reduce_while(components, {:ok, initial}, fn
          component, {:ok, stack} when component in ["", "."] ->
            {:cont, {:ok, stack}}

          "..", {:ok, []} ->
            {:halt, {:error, "#{link_path}: symlink target escapes the artifact root"}}

          "..", {:ok, stack} ->
            {:cont, {:ok, tl(stack)}}

          component, {:ok, stack} ->
            {:cont, {:ok, [component | stack]}}
        end)

      case result do
        {:ok, []} -> {:error, "#{link_path}: symlink target resolves to the artifact root"}
        {:ok, reversed} -> {:ok, Enum.join(Enum.reverse(reversed), "/")}
        {:error, _} = error -> error
      end
    else
      {:error, "#{link_path}: symlink target must be relative UTF-8"}
    end
  end

  defp normalized_link_target(link_path, _),
    do: {:error, "#{link_path}: symlink target must be relative UTF-8"}

  defp bounded_shape(value, max_depth, max_nodes) do
    case shape(value, 1, 0, max_depth, max_nodes) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp shape(_, depth, _, max_depth, _) when depth > max_depth,
    do: {:error, "payload manifest exceeds nesting depth #{max_depth}"}

  defp shape(_, _, nodes, _, max_nodes) when nodes >= max_nodes,
    do: {:error, "payload manifest exceeds #{max_nodes} values"}

  defp shape(value, depth, nodes, max_depth, max_nodes) when is_map(value) do
    Enum.reduce_while(value, {:ok, nodes + 1}, fn {key, item}, {:ok, count} ->
      with {:ok, after_key} <- shape(key, depth + 1, count, max_depth, max_nodes),
           {:ok, after_value} <- shape(item, depth + 1, after_key, max_depth, max_nodes) do
        {:cont, {:ok, after_value}}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp shape(value, depth, nodes, max_depth, max_nodes) when is_list(value) do
    Enum.reduce_while(value, {:ok, nodes + 1}, fn item, {:ok, count} ->
      case shape(item, depth + 1, count, max_depth, max_nodes) do
        {:ok, after_item} -> {:cont, {:ok, after_item}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp shape(_, _, nodes, _, _), do: {:ok, nodes + 1}

  defp decode_json(bytes) do
    case JSON.decode(bytes) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, error} -> {:error, "invalid payload manifest JSON: #{Exception.message(error)}"}
    end
  rescue
    error -> {:error, "invalid payload manifest JSON: #{Exception.message(error)}"}
  end

  defp identity_value(value, path) do
    case CanonicalJSON.encode(value) do
      {:ok, _} -> :ok
      {:error, message} -> {:error, String.replace_prefix(message, "$", path)}
    end
  end

  defp nonempty_string(value, path) do
    if is_binary(value) and value != "" and String.valid?(value),
      do: :ok,
      else: {:error, "#{path}: expected a non-empty UTF-8 string"}
  end

  defp full_digest(value, path) do
    if is_binary(value) and Regex.match?(@digest, value),
      do: :ok,
      else: {:error, "#{path}: expected a full lowercase SHA-256"}
  end
end
