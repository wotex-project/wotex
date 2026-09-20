defmodule Wotex.Workspace.NativeArtifact.CanonicalJSON do
  @moduledoc """
  Canonical JSON for native artifact identities.

  This is the integer-only RFC 8785 subset used by the artifact contract.
  Maps require UTF-8 string keys and are ordered by their UTF-16 code units.
  Floating-point values and language-specific terms are rejected.
  """

  @type value :: nil | boolean() | integer() | String.t() | [value()] | %{String.t() => value()}

  @doc "Encodes a value as canonical JSON."
  @spec encode(term()) :: {:ok, binary()} | {:error, String.t()}
  def encode(value) do
    case encode_value(value, "$") do
      {:ok, encoded} -> {:ok, IO.iodata_to_binary(encoded)}
      {:error, _} = error -> error
    end
  end

  @doc "Encodes a value as canonical JSON or raises `ArgumentError`."
  @spec encode!(term()) :: binary()
  def encode!(value) do
    case encode(value) do
      {:ok, encoded} -> encoded
      {:error, message} -> raise ArgumentError, message
    end
  end

  defp encode_value(nil, _), do: {:ok, "null"}
  defp encode_value(true, _), do: {:ok, "true"}
  defp encode_value(false, _), do: {:ok, "false"}
  defp encode_value(value, _) when is_integer(value), do: {:ok, Integer.to_string(value)}

  defp encode_value(value, path) when is_binary(value) do
    if String.valid?(value),
      do: {:ok, [?\", escape(value), ?\"]},
      else: {:error, "#{path}: strings must be valid UTF-8"}
  end

  defp encode_value(value, path) when is_list(value) do
    result =
      value
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, encoded} ->
        case encode_value(item, "#{path}[#{index}]") do
          {:ok, part} -> {:cont, {:ok, [part | encoded]}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case result do
      {:ok, encoded} -> {:ok, [?[, Enum.intersperse(Enum.reverse(encoded), ?,), ?]]}
      {:error, _} = error -> error
    end
  end

  defp encode_value(value, path) when is_map(value) do
    if Enum.all?(Map.keys(value), &(is_binary(&1) and String.valid?(&1))) do
      result =
        value
        |> Enum.sort_by(fn {key, _} ->
          :unicode.characters_to_binary(key, :utf8, {:utf16, :big})
        end)
        |> Enum.reduce_while({:ok, []}, fn {key, item}, {:ok, encoded} ->
          with {:ok, encoded_key} <- encode_value(key, path),
               {:ok, encoded_value} <- encode_value(item, "#{path}.#{key}") do
            {:cont, {:ok, [[encoded_key, ?:, encoded_value] | encoded]}}
          else
            {:error, _} = error -> {:halt, error}
          end
        end)

      case result do
        {:ok, encoded} -> {:ok, [?{, Enum.intersperse(Enum.reverse(encoded), ?,), ?}]}
        {:error, _} = error -> error
      end
    else
      {:error, "#{path}: map keys must be valid UTF-8 strings"}
    end
  end

  defp encode_value(value, path) when is_float(value),
    do: {:error, "#{path}: floating-point identity values are forbidden"}

  defp encode_value(_, path),
    do: {:error, "#{path}: value is outside the canonical JSON subset"}

  defp escape(value) do
    for <<codepoint::utf8 <- value>>, into: [] do
      case codepoint do
        ?\" ->
          "\\\""

        ?\\ ->
          "\\\\"

        0x08 ->
          "\\b"

        0x09 ->
          "\\t"

        0x0A ->
          "\\n"

        0x0C ->
          "\\f"

        0x0D ->
          "\\r"

        control when control < 0x20 ->
          hexadecimal = Integer.to_string(control, 16)
          ["\\u", String.pad_leading(hexadecimal, 4, "0")]

        other ->
          <<other::utf8>>
      end
    end
  end
end
