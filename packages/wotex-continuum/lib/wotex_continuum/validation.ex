defmodule WotexContinuum.Validation do
  @moduledoc false

  alias WotexContinuum.Error

  @max_identifier_bytes 512
  @digest ~r/^sha256:[0-9a-f]{64}$/

  @spec options(term(), [atom()]) :: :ok | {:error, Error.t()}
  def options(options, allowed) when is_list(options) and is_list(allowed) do
    cond do
      not Keyword.keyword?(options) ->
        Error.error(:invalid_options, [], "expected a unique keyword list")

      duplicate_options?(options) ->
        Error.error(:invalid_options, [], "option keys must be unique")

      unknown = Enum.find(Keyword.keys(options), &(&1 not in allowed)) ->
        Error.error(:unknown_field, [Atom.to_string(unknown)], "option is not defined")

      true ->
        :ok
    end
  end

  def options(_, _), do: Error.error(:invalid_options, [], "expected a unique keyword list")

  @spec struct_input(struct(), [atom()]) :: map()
  def struct_input(%_{} = value, nil_means_absent \\ []) do
    Enum.reduce(nil_means_absent, Map.from_struct(value), fn key, input ->
      if is_nil(Map.get(input, key)), do: Map.delete(input, key), else: input
    end)
  end

  @spec normalize(map(), [atom()]) :: {:ok, map()} | {:error, Error.t()}
  def normalize(%module{} = _, _) when is_atom(module) do
    Error.error(:invalid_type, [], "expected a plain object")
  end

  def normalize(data, allowed) when is_map(data) do
    by_string = Map.new(allowed, &{Atom.to_string(&1), &1})

    Enum.reduce_while(data, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      with {:ok, normalized_key} <- normalize_key(key, allowed, by_string),
           false <- Map.has_key?(acc, normalized_key) do
        {:cont, {:ok, Map.put(acc, normalized_key, value)}}
      else
        true ->
          {:halt,
           Error.error(
             :duplicate_field,
             [key_to_path(key)],
             "field appears in both atom and string form"
           )}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  def normalize(_, _), do: Error.error(:invalid_type, [], "expected an object")

  @spec required(map(), atom()) :: {:ok, term()} | {:error, Error.t()}
  def required(data, key) do
    case Map.fetch(data, key) do
      {:ok, value} -> {:ok, value}
      :error -> Error.error(:required, [Atom.to_string(key)], "field is required")
    end
  end

  @spec string(term(), [Error.segment()], keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def string(value, path, opts \\ [])

  def string(value, path, opts) when is_binary(value) do
    min = Keyword.get(opts, :min, 1)
    max = Keyword.get(opts, :max, @max_identifier_bytes)
    size = byte_size(value)

    cond do
      not String.valid?(value) -> Error.error(:invalid_utf8, path, "expected valid UTF-8")
      size < min -> Error.error(:too_short, path, "string is shorter than the allowed minimum")
      size > max -> Error.error(:too_long, path, "string exceeds the allowed maximum")
      true -> {:ok, value}
    end
  end

  def string(_, path, _), do: Error.error(:invalid_type, path, "expected a string")

  @spec optional_string(term(), [Error.segment()], keyword()) ::
          {:ok, String.t() | nil} | {:error, Error.t()}
  def optional_string(nil, _, _), do: {:ok, nil}
  def optional_string(value, path, opts), do: string(value, path, opts)

  @spec iri(term(), [Error.segment()]) :: {:ok, String.t()} | {:error, Error.t()}
  def iri(value, path) do
    with {:ok, value} <- string(value, path),
         %URI{scheme: scheme} when is_binary(scheme) and scheme != "" <- URI.parse(value) do
      {:ok, value}
    else
      {:error, _} = error -> error
      _ -> Error.error(:invalid_iri, path, "expected an absolute IRI")
    end
  end

  @spec digest(term(), [Error.segment()]) :: {:ok, String.t()} | {:error, Error.t()}
  def digest(value, path) do
    with {:ok, value} <- string(value, path, max: 128),
         true <- Regex.match?(@digest, value) do
      {:ok, value}
    else
      {:error, _} = error -> error
      false -> Error.error(:invalid_digest, path, "expected a lowercase sha256 digest")
    end
  end

  @spec semver(term(), [Error.segment()]) :: {:ok, String.t()} | {:error, Error.t()}
  def semver(value, path) do
    with {:ok, value} <- string(value, path, max: 128),
         {:ok, _} <- Version.parse(value) do
      {:ok, value}
    else
      {:error, %Error{}} = error -> error
      :error -> Error.error(:invalid_version, path, "expected a semantic version")
    end
  end

  @spec version_requirement(term(), [Error.segment()]) ::
          {:ok, String.t()} | {:error, Error.t()}
  def version_requirement(value, path) do
    with {:ok, value} <- string(value, path, max: 256),
         {:ok, _} <- Version.parse_requirement(value) do
      {:ok, value}
    else
      {:error, %Error{}} = error -> error
      :error -> Error.error(:invalid_version_requirement, path, "expected a version requirement")
    end
  end

  @spec timestamp(term(), [Error.segment()]) :: {:ok, String.t()} | {:error, Error.t()}
  def timestamp(%DateTime{} = value, _), do: {:ok, normalize_datetime(value)}

  def timestamp(value, path) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} -> {:ok, normalize_datetime(datetime)}
      {:error, _} -> Error.error(:invalid_timestamp, path, "expected an RFC 3339 timestamp")
    end
  end

  def timestamp(_, path), do: Error.error(:invalid_type, path, "expected a timestamp string")

  @spec enum(term(), [Error.segment()], [atom()]) :: {:ok, atom()} | {:error, Error.t()}
  def enum(value, path, allowed) when is_atom(value) do
    if value in allowed,
      do: {:ok, value},
      else: Error.error(:invalid_enum, path, "value is not in the allowed set")
  end

  def enum(value, path, allowed) when is_binary(value) do
    case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
      nil -> Error.error(:invalid_enum, path, "value is not in the allowed set")
      atom -> {:ok, atom}
    end
  end

  def enum(_, path, _), do: Error.error(:invalid_type, path, "expected an enum string")

  @spec boolean(term(), [Error.segment()]) :: {:ok, boolean()} | {:error, Error.t()}
  def boolean(value, _) when is_boolean(value), do: {:ok, value}
  def boolean(_, path), do: Error.error(:invalid_type, path, "expected a boolean")

  @spec non_negative_integer(term(), [Error.segment()]) ::
          {:ok, non_neg_integer()} | {:error, Error.t()}
  def non_negative_integer(value, _) when is_integer(value) and value >= 0, do: {:ok, value}

  def non_negative_integer(_, path) do
    Error.error(:invalid_integer, path, "expected a non-negative integer")
  end

  @spec positive_integer(term(), [Error.segment()]) ::
          {:ok, pos_integer()} | {:error, Error.t()}
  def positive_integer(value, _) when is_integer(value) and value > 0, do: {:ok, value}

  def positive_integer(_, path) do
    Error.error(:invalid_integer, path, "expected a positive integer")
  end

  @spec json_value(term(), [Error.segment()]) :: {:ok, term()} | {:error, Error.t()}
  def json_value(value, path), do: json_value(value, path, 0)

  defp json_value(value, _, _)
       when is_nil(value) or is_boolean(value) or is_integer(value),
       do: {:ok, value}

  defp json_value(value, path, _) when is_binary(value) do
    if String.valid?(value),
      do: {:ok, value},
      else: Error.error(:invalid_utf8, path, "expected valid UTF-8")
  end

  defp json_value(value, path, _) when is_float(value) do
    if finite_float?(value),
      do: {:ok, value},
      else: Error.error(:invalid_number, path, "expected a finite JSON number")
  end

  defp json_value(value, path, depth) when is_list(value) and depth < 64 do
    map_list(value, path, &json_value(&1, &2, depth + 1))
  end

  defp json_value(value, path, depth) when is_map(value) and not is_struct(value) and depth < 64 do
    Enum.reduce_while(value, {:ok, %{}}, &normalize_json_member(&1, &2, path, depth))
  end

  defp json_value(value, path, depth) when (is_list(value) or is_map(value)) and depth >= 64 do
    Error.error(:limit_exceeded, path, "JSON value exceeds the nesting limit")
  end

  defp json_value(_, path, _),
    do: Error.error(:invalid_json_value, path, "expected a JSON value")

  defp normalize_json_member({key, item}, {:ok, acc}, path, depth) when is_binary(key) do
    case json_value(item, child_path(path, key), depth + 1) do
      {:ok, normalized} -> {:cont, {:ok, Map.put(acc, key, normalized)}}
      {:error, _} = error -> {:halt, error}
    end
  end

  defp normalize_json_member({_, _}, _, path, _) do
    {:halt, Error.error(:invalid_key, path, "JSON object keys must be strings")}
  end

  @spec extensions(term(), [Error.segment()]) :: {:ok, map()} | {:error, Error.t()}
  def extensions(value, path) when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, item}, {:ok, acc} ->
      with {:ok, key} <- iri(key, path),
           {:ok, item} <- json_value(item, child_path(path, key)) do
        {:cont, {:ok, Map.put(acc, key, item)}}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  def extensions(_, path), do: Error.error(:invalid_type, path, "expected an extension object")

  @spec string_list(term(), [Error.segment()], keyword()) ::
          {:ok, [String.t()]} | {:error, Error.t()}
  def string_list(value, path, opts \\ []) do
    with {:ok, list} <- list(value, path),
         {:ok, strings} <- map_list(list, path, &string(&1, &2, opts)),
         :ok <- uniqueness(strings, path),
         :ok <- minimum_length(strings, path, Keyword.get(opts, :list_min, 0)) do
      {:ok, strings}
    end
  end

  @spec enum_list(term(), [Error.segment()], [atom()], keyword()) ::
          {:ok, [atom()]} | {:error, Error.t()}
  def enum_list(value, path, allowed, opts \\ []) do
    with {:ok, list} <- list(value, path),
         {:ok, enums} <- map_list(list, path, &enum(&1, &2, allowed)),
         :ok <- uniqueness(enums, path),
         :ok <- minimum_length(enums, path, Keyword.get(opts, :min, 0)) do
      {:ok, enums}
    end
  end

  @spec structs(term(), [Error.segment()], module()) ::
          {:ok, [struct()]} | {:error, Error.t()}
  def structs(value, path, module) do
    with {:ok, list} <- list(value, path) do
      map_list(list, path, &construct_struct(&1, &2, module))
    end
  end

  defp construct_struct(item, item_path, module) do
    case module.new(item) do
      {:ok, struct} -> {:ok, struct}
      {:error, %Error{} = error} -> {:error, prepend_path(error, item_path)}
    end
  end

  @spec nested(term(), [Error.segment()], module()) :: {:ok, struct()} | {:error, Error.t()}
  def nested(value, path, module) do
    case module.new(value) do
      {:ok, struct} -> {:ok, struct}
      {:error, %Error{} = error} -> {:error, prepend_path(error, path)}
    end
  end

  @spec list(term(), [Error.segment()]) :: {:ok, list()} | {:error, Error.t()}
  def list(value, _) when is_list(value), do: {:ok, value}
  def list(_, path), do: Error.error(:invalid_type, path, "expected an array")

  @spec uniqueness(list(), [Error.segment()]) :: :ok | {:error, Error.t()}
  def uniqueness(values, path) do
    if length(values) == MapSet.size(MapSet.new(values)),
      do: :ok,
      else: Error.error(:duplicate_value, path, "array members must be unique")
  end

  @spec map_list(list(), [Error.segment()], (term(), [Error.segment()] ->
                                               {:ok, term()} | {:error, Error.t()})) ::
          {:ok, list()} | {:error, Error.t()}
  def map_list(values, path, mapper) do
    result =
      values
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {value, index}, {:ok, acc} ->
        case mapper.(value, child_path(path, index)) do
          {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case result do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, _} = error -> error
    end
  end

  @spec to_wire(term()) :: term()
  def to_wire(%module{} = value) do
    if function_exported?(module, :to_map, 1), do: module.to_map(value), else: value
  end

  def to_wire(value) when is_list(value), do: Enum.map(value, &to_wire/1)

  def to_wire(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), to_wire(item)} end)
  end

  def to_wire(value) when is_atom(value) and value not in [nil, true, false],
    do: Atom.to_string(value)

  def to_wire(value), do: value

  @spec compare_timestamps(String.t(), String.t()) :: :lt | :eq | :gt
  def compare_timestamps(left, right) do
    {:ok, left_datetime, _} = DateTime.from_iso8601(left)
    {:ok, right_datetime, _} = DateTime.from_iso8601(right)
    DateTime.compare(left_datetime, right_datetime)
  end

  defp normalize_key(key, allowed, _) when is_atom(key) do
    if key in allowed,
      do: {:ok, key},
      else: Error.error(:unknown_field, [Atom.to_string(key)], "field is not defined")
  end

  defp normalize_key(key, _, by_string) when is_binary(key) do
    case Map.fetch(by_string, key) do
      {:ok, atom} -> {:ok, atom}
      :error -> Error.error(:unknown_field, [key], "field is not defined")
    end
  end

  defp normalize_key(_, _, _) do
    Error.error(:invalid_key, [], "object keys must be strings or known atoms")
  end

  defp key_to_path(key) when is_atom(key), do: Atom.to_string(key)
  defp key_to_path(key) when is_binary(key), do: key
  defp key_to_path(_), do: "?"

  defp minimum_length(values, path, minimum) do
    if length(values) >= minimum,
      do: :ok,
      else: Error.error(:too_short, path, "array is shorter than the allowed minimum")
  end

  defp duplicate_options?(options) do
    keys = Keyword.keys(options)
    length(keys) != MapSet.size(MapSet.new(keys))
  end

  defp normalize_datetime(datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp finite_float?(value) do
    <<_::1, exponent::11, _::52>> = <<value::float-64>>
    exponent != 0x7FF
  end

  defp prepend_path(%Error{} = error, path) do
    %{error | path: path ++ error.path}
  end

  defp child_path(path, segment), do: Enum.concat(path, [segment])
end
