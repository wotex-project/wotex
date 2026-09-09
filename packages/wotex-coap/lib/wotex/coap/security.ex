defmodule Wotex.CoAP.Security do
  @moduledoc """
  Holds an explicitly selected DTLS credential without exposing its secret through Inspect.

  The PSK value binds one UTF-8 client identity to one binary key. Construction
  validates values only; it does not start SSL, open a connection or select another
  credential from an unauthenticated peer hint. Consumers own credential custody
  and rotation. A value does not prove that a transport supports its cipher suite.
  """

  alias Wotex.CoAP.Error
  alias Wotex.CoAP.Security.PKI
  @derive {Inspect, only: [:mode]}
  @enforce_keys [:mode]
  defstruct [
    :mode,
    :identity,
    :key,
    :trust_roots,
    :certificate,
    :private_key,
    :server_identity,
    :crls
  ]

  @psk_keys [:mode, :identity, :key]
  @pki_keys [:mode, :trust_roots, :certificate, :private_key, :server_identity, :crls]

  @opaque t :: %__MODULE__{
            mode: :dtls_psk | :dtls_pki,
            identity: String.t() | nil,
            key: binary() | nil,
            trust_roots: [binary()] | nil,
            certificate: binary() | nil,
            private_key: binary() | nil,
            server_identity: {:dns, String.t()} | {:ip, :inet.ip_address()} | nil,
            crls: [binary()] | nil
          }

  @doc """
  Constructs a credential from an exact atom-keyed map or unique keyword list.

  Required keys are `:mode` (`:dtls_psk`), `:identity` (1..128 UTF-8 bytes without
  ASCII controls), and `:key` (16..64 binary bytes). Unknown keys, duplicate options,
  malformed lists and unsupported modes return a structured error. There is no
  default identity or key; error values contain neither.

  PKI uses `:mode` (`:dtls_pki`), `:trust_roots` and `:crls` (1..8 DER binaries
  each), `:certificate` (DER client certificate), `:private_key` (unencrypted DER
  PKCS#1 or PKCS#8 for two-prime RSA), and `:server_identity` (`{:dns, ascii_name}` or
  `{:ip, numeric_tuple}`). Each binary is at most 64 KiB, with a 1 MiB aggregate
  limit. RSA keys require at least 2048 bits and the client key must match its
  certificate. Construction parses immutable material without consulting clocks;
  time, chain, peer identity and revocation are checked during the handshake.
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

  def new(%{mode: :dtls_pki} = values) when map_size(values) == 6 do
    with true <- Map.keys(values) -- @pki_keys == [],
         :ok <- PKI.validate(values),
         do: {:ok, struct!(__MODULE__, values)},
         else: (_ -> failure(:pki))
  end

  def new(_), do: failure(:security)

  @doc "Revalidates an exact credential value before a transport can acquire a resource."
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(%__MODULE__{} = value) when map_size(value) == 9 do
    keys = if value.mode == :dtls_psk, do: @psk_keys, else: @pki_keys

    case new(Map.take(Map.from_struct(value), keys)) do
      {:ok, ^value} -> :ok
      {:error, %Error{}} = error -> error
      _ -> failure(:security)
    end
  end

  def validate(_), do: failure(:security)

  defp options([], values), do: {:ok, values}

  defp options([{key, value} | rest], values)
       when key in @psk_keys or key in @pki_keys,
       do:
         if(is_map_key(values, key),
           do: failure(:security),
           else: options(rest, Map.put(values, key, value))
         )

  defp options(_, _), do: failure(:security)

  defp identity?(value) when is_binary(value) and byte_size(value) in 1..128,
    do: String.valid?(value) and not Regex.match?(~r/[\x00-\x1F\x7F]/, value)

  defp identity?(_), do: false
  defp failure(field), do: {:error, Error.new(:invalid_security, field)}
end
