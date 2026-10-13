defmodule Wotex.Routines.Validation do
  @moduledoc false

  alias Wotex.Routines.{Error, Limits}

  @type checked :: :ok | {:error, Error.t()}

  @doc false
  @spec admit(term(), term(), module() | nil) ::
          {:ok, term(), Limits.t()} | {:error, Error.t()}
  def admit(input, limits, module) do
    with {:ok, limits} <- Limits.new(limits),
         {:ok, data} <- unpack(input, module),
         :ok <- bounded(data, limits) do
      {:ok, data, limits}
    end
  end

  @doc false
  @spec bounded(term(), Limits.t()) :: checked()
  def bounded(data, %Limits{data: limits}) do
    opts = json_options(limits)

    with :ok <- Wotex.JSON.validate(data, opts),
         :ok <- integer_magnitudes(data, limits["max_integer"]),
         {:ok, bytes} <- Wotex.JSON.encode(data, opts),
         true <- byte_size(bytes) <= limits["max_bytes"] do
      :ok
    else
      {:error, %Error{}} = error -> error
      _ -> Error.refusal(:limit_or_json_error)
    end
  end

  defp integer_magnitudes(value, maximum) when is_integer(value) do
    if abs(value) <= maximum, do: :ok, else: Error.refusal(:integer_overflow)
  end

  defp integer_magnitudes(values, maximum) when is_list(values),
    do: each(values, &integer_magnitudes(&1, maximum))

  defp integer_magnitudes(value, maximum) when is_map(value),
    do: each(Map.values(value), &integer_magnitudes(&1, maximum))

  defp integer_magnitudes(_, _), do: :ok

  @doc false
  @spec json_options(map()) :: keyword(pos_integer())
  def json_options(limits) do
    Enum.map(~w(max_bytes max_depth max_nodes max_string_bytes max_collection_size)a, fn key ->
      {key, limits[Atom.to_string(key)]}
    end)
  end

  @doc false
  @spec unpack(term(), module() | nil) :: {:ok, term()} | {:error, Error.t()}
  def unpack(%{__struct__: module, data: data} = value, module)
      when module != nil and map_size(value) == 2,
      do: {:ok, data}

  def unpack(value, _) when is_struct(value), do: Error.refusal(:invalid_struct)
  def unpack(value, _), do: {:ok, value}

  @doc false
  @spec fields(term(), [String.t()], [String.t()], String.t()) :: checked()
  def fields(data, required, optional \\ [], path \\ "") do
    cond do
      not is_map(data) ->
        Error.refusal(:invalid_type, path)

      Enum.any?(required, &(not Map.has_key?(data, &1))) ->
        Error.refusal(:missing_field, path)

      Enum.any?(Map.keys(data), &(&1 not in (required ++ optional))) ->
        Error.refusal(:unknown_field, path)

      true ->
        :ok
    end
  end

  @doc false
  @spec text(term(), String.t()) :: checked()
  def text(value, path) do
    if is_binary(value) and byte_size(value) > 0 and String.valid?(value),
      do: :ok,
      else: Error.refusal(:invalid_string, path)
  end

  @doc false
  @spec digest(term(), String.t()) :: checked()
  def digest(value, path) do
    if is_binary(value) and Regex.match?(~r/^sha256:[0-9a-f]{64}$/, value),
      do: :ok,
      else: Error.refusal(:invalid_digest, path)
  end

  @doc false
  @spec integer(term(), Limits.t(), String.t(), integer() | nil) :: checked()
  def integer(value, %Limits{data: limits}, path, minimum \\ nil) do
    cond do
      not is_integer(value) -> Error.refusal(:invalid_type, path)
      abs(value) > limits["max_integer"] -> Error.refusal(:integer_overflow, path)
      not is_nil(minimum) and value < minimum -> Error.refusal(:out_of_domain, path)
      true -> :ok
    end
  end

  @doc false
  @spec choice(term(), list(), String.t()) :: checked()
  def choice(value, choices, path) do
    if value in choices, do: :ok, else: Error.refusal(:unsupported_value, path)
  end

  @doc false
  @spec boolean(term(), String.t()) :: checked()
  def boolean(value, path) do
    if is_boolean(value), do: :ok, else: Error.refusal(:invalid_type, path)
  end

  @doc false
  @spec strings(term(), String.t(), boolean()) :: checked()
  def strings(values, path, nonempty \\ false) do
    cond do
      not is_list(values) -> Error.refusal(:invalid_type, path)
      nonempty and values == [] -> Error.refusal(:missing_value, path)
      length(Enum.uniq(values)) != length(values) -> Error.refusal(:duplicate_identity, path)
      true -> each(values, &text(&1, path))
    end
  end

  @doc false
  @spec each(term(), (term() -> checked())) :: checked()
  def each(values, fun) when is_list(values) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      case fun.(value) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  def each(_, _), do: Error.refusal(:invalid_type)

  @doc false
  @spec timestamp(term(), String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def timestamp(value, path) do
    if is_binary(value) do
      case DateTime.from_iso8601(value) do
        {:ok, time, _} -> {:ok, DateTime.to_iso8601(time)}
        _ -> Error.refusal(:invalid_timestamp, path)
      end
    else
      Error.refusal(:invalid_timestamp, path)
    end
  end

  @doc false
  @spec iri(term(), String.t()) :: checked()
  def iri(value, path) do
    with :ok <- text(value, path),
         {:ok, %URI{scheme: scheme}} when is_binary(scheme) <- URI.new(value) do
      :ok
    else
      _ -> Error.refusal(:invalid_iri, path)
    end
  end

  @doc false
  @spec hash(term(), Limits.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def hash(data, limits) do
    case Wotex.JSON.encode(data, json_options(limits.data)) do
      {:ok, bytes} ->
        {:ok, "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)}

      _ ->
        Error.refusal(:limit_or_json_error)
    end
  end
end
