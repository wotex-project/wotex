defmodule Wotex.Profiles.Grammar do
  @moduledoc false
  alias Wotex.Profiles.{Error, Limits, Numeric}

  @doc false
  @spec admit(term(), term()) :: {:ok, term(), Limits.t()} | {:error, Error.t()}
  def admit(data, limits) do
    with {:ok, limits} <- Limits.new(limits),
         :ok <- Wotex.JSON.validate(data, options(limits)),
         :ok <- native(data, limits),
         {:ok, bytes} <- Wotex.JSON.encode(data, options(limits)),
         true <- byte_size(bytes) <= limits.data["max_bytes"] do
      {:ok, data, limits}
    else
      {:error, %Error{}} = error -> error
      _ -> Error.refusal(:input_limit)
    end
  end

  @doc false
  @spec options(Limits.t()) :: keyword()
  def options(limits) do
    [
      max_bytes: limits.data["max_bytes"],
      max_depth: limits.data["max_depth"],
      max_nodes: limits.data["max_nodes"],
      max_string_bytes: min(8192, limits.data["max_bytes"]),
      max_collection_size: 1024
    ]
  end

  defp native(value, limits) when is_integer(value) do
    if abs(value) < Integer.pow(10, limits.data["max_numeric_digits"]),
      do: :ok,
      else: Error.refusal(:numeric_limit)
  end

  defp native(value, _) when is_binary(value) do
    if String.valid?(value) and not String.contains?(value, <<0>>),
      do: :ok,
      else: Error.refusal(:invalid_input)
  end

  defp native(values, limits) when is_list(values), do: each(values, &native(&1, limits))

  defp native(value, limits) when is_map(value),
    do:
      each(Map.to_list(value), fn {key, child} ->
        with :ok <- native(key, limits), do: native(child, limits)
      end)

  defp native(value, limits) when is_float(value) do
    case Numeric.decimal(value, limits, "") do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp native(value, _) when is_boolean(value) or is_nil(value), do: :ok

  @doc false
  @spec fields(term(), [String.t()], String.t(), [String.t()]) :: :ok | {:error, Error.t()}
  def fields(data, required, path \\ "", optional \\ []) do
    if is_map(data) and not is_struct(data) and Enum.all?(required, &Map.has_key?(data, &1)) and
         Enum.all?(Map.keys(data), &(&1 in (required ++ optional))),
       do: :ok,
       else: Error.refusal(:invalid_input, path)
  end

  @doc false
  @spec text(term(), pos_integer(), String.t()) :: :ok | {:error, Error.t()}
  def text(value, maximum, path) do
    if is_binary(value) and byte_size(value) in 1..maximum and String.valid?(value) and
         not String.contains?(value, <<0>>), do: :ok, else: Error.refusal(:invalid_input, path)
  end

  @doc false
  @spec id(term(), String.t()) :: :ok | {:error, Error.t()}
  def id(value, path) do
    with :ok <- text(value, 256, path),
         {:ok, %URI{scheme: scheme}} when is_binary(scheme) <- URI.new(value) do
      :ok
    else
      _ -> Error.refusal(:invalid_input, path)
    end
  end

  @doc false
  @spec key(term(), String.t()) :: :ok | {:error, Error.t()}
  def key(value, path) do
    with :ok <- text(value, 128, path),
         true <- Regex.match?(~r/\A[a-zA-Z0-9._-]+\z/, value),
         do: :ok,
         else: (_ -> Error.refusal(:invalid_input, path))
  end

  @doc false
  @spec version(term(), String.t()) :: :ok | {:error, Error.t()}
  def version(value, path) do
    if is_binary(value) and byte_size(value) <= 17 and
         Regex.match?(~r/\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\z/, value) and
         Enum.all?(String.split(value, "."), &(String.to_integer(&1) <= 65_535)),
       do: :ok,
       else: Error.refusal(:invalid_input, path)
  end

  @doc false
  @spec reference(term(), String.t()) :: :ok | {:error, Error.t()}
  def reference(value, path) do
    with :ok <- fields(value, ~w(id version sha256), path),
         :ok <- id(value["id"], path),
         :ok <- version(value["version"], path),
         do: digest(value["sha256"], path)
  end

  @doc false
  @spec digest(term(), String.t()) :: :ok | {:error, Error.t()}
  def digest(value, path) do
    if is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value),
      do: :ok,
      else: Error.refusal(:invalid_input, path)
  end

  @doc false
  @spec references(term(), Limits.t(), String.t()) :: :ok | {:error, Error.t()}
  def references(values, limits, path) when is_list(values) do
    with true <- length(values) <= limits.data["max_dependencies"],
         :ok <- each(values, &reference(&1, path)) do
      sorted_unique(values, &{&1["id"], &1["version"]}, path)
    else
      false -> Error.refusal(:input_limit, path)
      error -> error
    end
  end

  def references(_, _, path), do: Error.refusal(:invalid_input, path)

  @doc false
  @spec sorted_unique(list(), (term() -> term()), String.t()) :: :ok | {:error, Error.t()}
  def sorted_unique(values, key, path) do
    keys = Enum.map(values, key)

    if keys == Enum.sort(keys) and length(Enum.uniq(keys)) == length(keys),
      do: :ok,
      else: Error.refusal(:reference_conflict, path)
  end

  @doc false
  @spec annotations(term()) :: :ok | {:error, Error.t()}
  def annotations(data) when is_map(data) and not is_struct(data) and map_size(data) <= 16 do
    with :ok <-
           each(Map.to_list(data), fn {key, value} ->
             with :ok <- text(key, 128, "/annotations"),
                  true <- is_binary(value),
                  true <- byte_size(value) <= 1024,
                  do: :ok,
                  else: (_ -> Error.refusal(:invalid_input, "/annotations"))
           end),
         {:ok, bytes} <- Wotex.JSON.encode(data),
         true <- byte_size(bytes) <= 8192 do
      :ok
    else
      _ -> Error.refusal(:input_limit, "/annotations")
    end
  end

  def annotations(_), do: Error.refusal(:invalid_input, "/annotations")

  @doc false
  @spec optional_annotations(map()) :: :ok | {:error, Error.t()}
  def optional_annotations(data) do
    if Map.has_key?(data, "annotations"), do: annotations(data["annotations"]), else: :ok
  end

  @doc false
  @spec scalar(term(), [String.t()], String.t()) :: :ok | {:error, Error.t()}
  def scalar(value, types, path) do
    with {:ok, value} <- Wotex.Runtime.Codec.Value.validate(value),
         true <- value["type"] in types do
      :ok
    else
      _ -> Error.refusal(:invalid_input, path)
    end
  end

  @doc false
  @spec unique_scalars(term(), non_neg_integer(), [String.t()], String.t()) ::
          :ok | {:error, Error.t()}
  def unique_scalars(values, maximum, types, path) when is_list(values) do
    with true <- length(values) <= maximum,
         :ok <- each(values, &scalar(&1, types, path)) do
      encoded =
        Enum.map(values, fn value ->
          {:ok, bytes} = Wotex.Runtime.Codec.Value.encode(value)
          bytes
        end)

      if length(Enum.uniq(encoded)) == length(encoded),
        do: :ok,
        else: Error.refusal(:invalid_input, path)
    else
      false -> Error.refusal(:input_limit, path)
      error -> error
    end
  end

  def unique_scalars(_, _, _, path), do: Error.refusal(:invalid_input, path)

  @doc false
  @spec each(term(), (term() -> :ok | {:error, Error.t()})) :: :ok | {:error, Error.t()}
  def each(values, function) when is_list(values) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      case function.(value) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  def each(_, _), do: Error.refusal(:invalid_input)

  @doc false
  @spec hash(binary()) :: String.t()
  def hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  @doc false
  @spec identity(String.t(), map(), Limits.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def identity(prefix, data, limits) do
    case Wotex.JSON.encode(Map.delete(data, "annotations"), options(limits)) do
      {:ok, bytes} -> {:ok, hash(prefix <> "\n" <> bytes)}
      _ -> Error.refusal(:input_limit)
    end
  end
end
