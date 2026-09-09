defmodule Wotex.CoAP.Security do
  @moduledoc """
  Holds an explicitly selected DTLS credential without exposing its secret through Inspect.

  The PSK value binds one UTF-8 client identity to one binary key. Construction
  validates values only; it does not start SSL, open a connection or select another
  credential from an unauthenticated peer hint. Consumers own credential custody
  and rotation. A value does not prove that a transport supports its cipher suite.
  """

  alias Wotex.CoAP.Error
  @derive {Inspect, only: [:mode]}
  @enforce_keys [:mode, :identity, :key]
  defstruct [:mode, :identity, :key]

  @opaque t :: %__MODULE__{mode: :dtls_psk, identity: String.t(), key: binary()}

  @doc """
  Constructs a PSK credential from an exact atom-keyed map or unique keyword list.

  Required keys are `:mode` (`:dtls_psk`), `:identity` (1..128 UTF-8 bytes without
  ASCII controls), and `:key` (16..64 binary bytes). Unknown keys, duplicate options,
  malformed lists and unsupported modes return a structured error. There is no
  default identity or key; error values contain neither.
  """
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(options) when is_list(options) do
    with {:ok, values} <- options(options, %{}), do: new(values)
  end

  def new(%{mode: :dtls_psk, identity: identity, key: key} = values) when map_size(values) == 3 do
    cond do
      not identity?(identity) -> failure(:identity)
      not is_binary(key) or byte_size(key) not in 16..64 -> failure(:key)
      true -> {:ok, %__MODULE__{mode: :dtls_psk, identity: identity, key: key}}
    end
  end

  def new(_), do: failure(:security)

  @doc "Revalidates an exact credential value before a transport can acquire a resource."
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(%__MODULE__{} = value) when map_size(value) == 4 do
    case new(Map.from_struct(value)) do
      {:ok, ^value} -> :ok
      {:error, %Error{}} = error -> error
      _ -> failure(:security)
    end
  end

  def validate(_), do: failure(:security)

  defp options([], values), do: {:ok, values}

  defp options([{key, value} | rest], values)
       when key in [:mode, :identity, :key] and not is_map_key(values, key),
       do: options(rest, Map.put(values, key, value))

  defp options(_, _), do: failure(:security)

  defp identity?(value) when is_binary(value) and byte_size(value) in 1..128,
    do: String.valid?(value) and not Regex.match?(~r/[\x00-\x1F\x7F]/, value)

  defp identity?(_), do: false
  defp failure(field), do: {:error, Error.new(:invalid_security, field)}
end
