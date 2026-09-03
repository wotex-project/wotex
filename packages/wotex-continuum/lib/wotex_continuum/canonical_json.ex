defmodule WotexContinuum.CanonicalJSON do
  @moduledoc """
  Deterministic JSON encoder for continuum wire values.

  Object keys are ordered by UTF-8 bytes, list order is preserved, and no
  insignificant whitespace is emitted. The form is project-defined and does
  not claim RFC 8785 conformance.
  """

  alias WotexContinuum.Error

  @doc "Encodes a JSON-compatible value into deterministic JSON bytes."
  @spec encode(term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(value) do
    with {:ok, iodata} <- encode_value(value, []) do
      {:ok, IO.iodata_to_binary(iodata)}
    end
  end

  defp encode_value(nil, _), do: {:ok, "null"}
  defp encode_value(true, _), do: {:ok, "true"}
  defp encode_value(false, _), do: {:ok, "false"}
  defp encode_value(value, _) when is_integer(value), do: {:ok, Integer.to_string(value)}

  defp encode_value(value, path) when is_float(value) do
    case Jason.encode(value) do
      {:ok, encoded} -> {:ok, encoded}
      {:error, _} -> Error.error(:invalid_number, path, "expected a finite JSON number")
    end
  end

  defp encode_value(value, path) when is_binary(value) do
    if String.valid?(value) do
      case Jason.encode(value) do
        {:ok, encoded} -> {:ok, encoded}
        {:error, _} -> Error.error(:invalid_string, path, "cannot encode the string")
      end
    else
      Error.error(:invalid_utf8, path, "expected valid UTF-8")
    end
  end

  defp encode_value(value, path) when is_list(value) do
    with {:ok, items} <- encode_list(value, path) do
      {:ok, [?[, Enum.intersperse(items, ?,), ?]]}
    end
  end

  defp encode_value(value, path) when is_map(value) and not is_struct(value) do
    with {:ok, pairs} <- encode_map(value, path) do
      {:ok, [?{, Enum.intersperse(pairs, ?,), ?}]}
    end
  end

  defp encode_value(_, path),
    do: Error.error(:invalid_json_value, path, "expected a JSON value")

  defp encode_list(values, path) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {value, index}, {:ok, acc} ->
      case encode_value(value, child_path(path, index)) do
        {:ok, encoded} -> {:cont, {:ok, [encoded | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> reverse_result()
  end

  defp encode_map(map, path) do
    if Enum.all?(map, fn {key, _} -> is_binary(key) end) do
      map
      |> Enum.sort_by(fn {key, _} -> key end)
      |> Enum.reduce_while({:ok, []}, &encode_pair(&1, &2, path))
      |> reverse_result()
    else
      Error.error(:invalid_key, path, "JSON object keys must be strings")
    end
  end

  defp encode_pair({key, value}, {:ok, acc}, path) do
    key_path = child_path(path, key)

    with {:ok, encoded_key} <- encode_value(key, key_path),
         {:ok, encoded_value} <- encode_value(value, key_path) do
      {:cont, {:ok, [[encoded_key, ?:, encoded_value] | acc]}}
    else
      {:error, _} = error -> {:halt, error}
    end
  end

  defp reverse_result({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_result({:error, _} = error), do: error

  defp child_path(path, segment), do: Enum.concat(path, [segment])
end
