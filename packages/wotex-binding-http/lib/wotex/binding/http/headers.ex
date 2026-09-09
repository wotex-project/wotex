defmodule Wotex.Binding.HTTP.Headers do
  @moduledoc """
  Validates and deterministically composes credential-free HTTP fields.

  Names are normalized to lowercase and duplicates are rejected. Credential,
  connection, host, and message-framing fields stay under the supplied client's
  control and cannot enter a request through static configuration or TD Forms.

  `new/2` validates field-name tokens and text values for request or response
  use. Request construction rejects connection-specific framing fields;
  credential-bearing fields are rejected in both directions. `merge/2` and
  `put/3` compose already validated lists deterministically, and `get/2`
  performs a case-insensitive lookup against their normalized names.

  A `t:t/0` preserves field order and original values while representing names
  in lowercase. The module does not apply an execution credential, calculate
  Content-Length, or choose HTTP connection behavior. The supplied client owns
  those operations at the immediate network boundary.
  """

  alias Wotex.Binding.HTTP.Error

  @credential_fields ~w(authorization proxy-authorization cookie set-cookie)
  @framing_fields ~w(connection content-length host keep-alive proxy-connection te trailer transfer-encoding upgrade)
  @token ~r/\A[!#$%&'*+\-.^_`|~0-9A-Za-z]+\z/
  @invalid_value ~r/[\x00-\x08\x0A-\x1F\x7F]/

  @type t :: [{String.t(), String.t()}]
  @type kind :: :request | :response

  @doc "Validates and lowercases a list of HTTP fields without changing field values."
  @spec new(term(), kind()) :: {:ok, t()} | {:error, Error.t()}
  def new(fields, kind \\ :request)

  def new(fields, kind) when is_list(fields) and kind in [:request, :response] do
    result =
      Enum.reduce_while(fields, {:ok, [], MapSet.new()}, fn field, {:ok, acc, seen} ->
        with {:ok, name, value} <- normalize_field(field, kind),
             false <- MapSet.member?(seen, name) do
          {:cont, {:ok, [{name, value} | acc], MapSet.put(seen, name)}}
        else
          true ->
            {:halt,
             {:error,
              Error.new(:duplicate_header, :request, "HTTP field names must be unique", %{
                name: normalized_name(field)
              })}}

          {:error, %Error{} = error} ->
            {:halt, {:error, error}}
        end
      end)

    case result do
      {:ok, normalized, _} -> {:ok, Enum.reverse(normalized)}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  def new(_, _) do
    {:error, Error.new(:invalid_headers, :request, "HTTP fields must be a list")}
  end

  @doc "Merges validated field lists, with the second list replacing matching names."
  @spec merge(t(), t()) :: t()
  def merge(base, overrides) when is_list(base) and is_list(overrides) do
    Enum.reduce(overrides, base, fn {name, value}, fields -> put(fields, name, value) end)
  end

  @doc "Sets one normalized field, replacing an existing case-insensitive match."
  @spec put(t(), String.t(), String.t()) :: t()
  def put(fields, name, value) when is_list(fields) and is_binary(name) and is_binary(value) do
    normalized = String.downcase(name)

    List.keystore(fields, normalized, 0, {normalized, value})
  end

  @doc "Returns a field value by case-insensitive name."
  @spec get(t(), String.t()) :: String.t() | nil
  def get(fields, name) when is_list(fields) and is_binary(name) do
    normalized = String.downcase(name)

    Enum.find_value(fields, fn
      {^normalized, value} -> value
      _ -> nil
    end)
  end

  @doc "Returns whether a binary is a valid HTTP token."
  @spec token?(term()) :: boolean()
  def token?(value), do: is_binary(value) and value != "" and Regex.match?(@token, value)

  defp normalize_field({name, value}, kind) when is_binary(name) and is_binary(value) do
    normalized = String.downcase(name)

    cond do
      not token?(name) ->
        {:error, Error.new(:invalid_header_name, :request, "HTTP field name is invalid")}

      normalized in @credential_fields ->
        {:error,
         Error.new(
           :credential_header_forbidden,
           :request,
           "credential-bearing HTTP fields must use the credential channel",
           %{name: normalized}
         )}

      kind == :request and normalized in @framing_fields ->
        {:error,
         Error.new(
           :framing_header_forbidden,
           :request,
           "HTTP framing fields are owned by the supplied client",
           %{name: normalized}
         )}

      not String.valid?(value) or Regex.match?(@invalid_value, value) ->
        {:error,
         Error.new(:invalid_header_value, :request, "HTTP field value contains invalid bytes", %{
           name: normalized
         })}

      true ->
        {:ok, normalized, value}
    end
  end

  defp normalize_field(_, _) do
    {:error,
     Error.new(:invalid_header, :request, "each HTTP field must be a binary name/value pair")}
  end

  defp normalized_name({name, _}) when is_binary(name), do: String.downcase(name)
  defp normalized_name(_), do: nil
end
