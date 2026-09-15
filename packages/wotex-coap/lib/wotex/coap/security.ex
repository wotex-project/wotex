defmodule Wotex.CoAP.Security do
  @moduledoc """
  Holds an explicitly selected DTLS or OSCORE credential without exposing secrets through Inspect.

  The PSK value binds one UTF-8 client identity to one binary key. The OSCORE
  value binds fixed-suite key material to one absolute durable context-store
  path. Construction validates values only; it does not start SSL, open a
  connection, read the context store or select a native executable. Consumers
  own credential custody and rotation. A value does not prove that a transport
  supports its cipher suite.
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
    :crls,
    :master_secret,
    :master_salt,
    :sender_id,
    :recipient_id,
    :id_context,
    :context_store
  ]

  @psk_keys [:mode, :identity, :key]
  @pki_keys [:mode, :trust_roots, :certificate, :private_key, :server_identity, :crls]
  @oscore_keys [
    :mode,
    :master_secret,
    :master_salt,
    :sender_id,
    :recipient_id,
    :id_context,
    :context_store
  ]

  @opaque t :: %__MODULE__{
            mode: :dtls_psk | :dtls_pki | :oscore,
            identity: String.t() | nil,
            key: binary() | nil,
            trust_roots: [binary()] | nil,
            certificate: binary() | nil,
            private_key: binary() | nil,
            server_identity: {:dns, String.t()} | {:ip, :inet.ip_address()} | nil,
            crls: [binary()] | nil,
            master_secret: binary() | nil,
            master_salt: binary() | nil,
            sender_id: binary() | nil,
            recipient_id: binary() | nil,
            id_context: binary() | nil,
            context_store: String.t() | nil
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

  OSCORE uses `:mode` (`:oscore`), `:master_secret` (16..32 bytes),
  `:master_salt` (0..32 bytes), distinct `:sender_id` and `:recipient_id`
  values (0..7 bytes), optional `:id_context` (0..255 bytes), and an absolute
  UTF-8 `:context_store` path of at most 4096 bytes without NUL. Omitting
  `:id_context` normalizes it to `nil`. Construction performs no filesystem I/O.
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

  def new(
        %{
          mode: :oscore,
          master_secret: master_secret,
          master_salt: master_salt,
          sender_id: sender_id,
          recipient_id: recipient_id,
          context_store: store
        } = values
      )
      when map_size(values) in [6, 7] do
    values = Map.put_new(values, :id_context, nil)

    with true <- Map.keys(values) -- @oscore_keys == [],
         :ok <- bounded_binary(master_secret, 16..32, :master_secret),
         :ok <- bounded_binary(master_salt, 0..32, :master_salt),
         :ok <- bounded_binary(sender_id, 0..7, :sender_id),
         :ok <- bounded_binary(recipient_id, 0..7, :recipient_id),
         true <- sender_id != recipient_id,
         :ok <- optional_binary(values.id_context, 0..255, :id_context),
         :ok <- context_store(store),
         do: {:ok, struct!(__MODULE__, values)},
         else: (
           {:error, %Error{}} = error -> error
           _ -> failure(:sender_id)
         )
  end

  def new(_), do: failure(:security)

  @doc "Revalidates an exact credential value before a transport can acquire a resource."
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(%__MODULE__{} = value) when map_size(value) == 15 do
    with {:ok, keys} <- validation_keys(value.mode) do
      case new(Map.take(Map.from_struct(value), keys)) do
        {:ok, ^value} -> :ok
        {:error, %Error{}} = error -> error
        _ -> failure(:security)
      end
    end
  end

  def validate(_), do: failure(:security)

  defp options([], values), do: {:ok, values}

  defp options([{key, value} | rest], values)
       when key in @psk_keys or key in @pki_keys or key in @oscore_keys,
       do:
         if(is_map_key(values, key),
           do: failure(:security),
           else: options(rest, Map.put(values, key, value))
         )

  defp options(_, _), do: failure(:security)

  defp identity?(value) when is_binary(value) and byte_size(value) in 1..128,
    do: String.valid?(value) and not Regex.match?(~r/[\x00-\x1F\x7F]/, value)

  defp identity?(_), do: false

  defp validation_keys(:dtls_psk), do: {:ok, @psk_keys}
  defp validation_keys(:dtls_pki), do: {:ok, @pki_keys}
  defp validation_keys(:oscore), do: {:ok, @oscore_keys}
  defp validation_keys(_), do: failure(:security)

  defp bounded_binary(value, range, field) do
    if is_binary(value) and byte_size(value) in range, do: :ok, else: failure(field)
  end

  defp optional_binary(nil, _, _), do: :ok
  defp optional_binary(value, range, field), do: bounded_binary(value, range, field)

  defp context_store(value)
       when is_binary(value) and byte_size(value) in 1..4096 do
    if String.valid?(value) and :binary.match(value, <<0>>) == :nomatch and
         Path.type(value) == :absolute,
       do: :ok,
       else: failure(:context_store)
  end

  defp context_store(_), do: failure(:context_store)
  defp failure(field), do: {:error, Error.new(:invalid_security, field)}
end
