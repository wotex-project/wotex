defmodule Wotex.Zigbee.Credentials do
  @moduledoc """
  An explicit consumer-owned credential custody and authorization port.

  The handle is a pid or reference into consumer custody, never key bytes,
  counters, a file path or store configuration. Constructing this value starts
  nothing. The consumer provisions, supervises and qualifies its adapter and
  resident coordinator credentials, Trust Center policy, install-code support
  and any enrollment fallback. Metadata does not establish those properties.

  Before each local permit-join, channel migration or key-rotation phase, the owner supplies a
  fresh `Wotex.Zigbee.Network.Snapshot`, the exact request, owner epoch, current
  monotonic time and original deadline. `c:authorize/3` must check current
  consumer policy and qualified custody for that exact network and operation.
  Return `{:ok, expires_at_ms}` for a finite monotonic authorization horizon,
  or `{:error, reason}` to deny. Authorization returns no key or counter material.

  For migration, custody must qualify the exact firmware's network-manager
  support, update-ID headroom (the pinned parser uses the current ID plus one
  and its receiver compares unsigned IDs without wrap recovery), administrative
  pacing and the requested delay against its configured broadcast delivery
  time. Deny unsupported firmware, exhausted IDs, competing administration or
  an unqualified delay. The port grants permission, not proof of radio effect.

  Key rotation requires separate `:update` and `:switch` authorization. Each
  context includes fresh network metadata; the switch context also retains the
  update admission. Qualify the exact firmware/build's key commands and security
  mode, active sequence, a unique fresh key, counter continuity, distribution
  policy, pacing and both delays. Metadata contains no key-sequence proof.
  Deny unqualified firmware, sequences/counters, delays or distribution policy.

  The optional `c:with_network_key/4` callback runs only after update authorization.
  It obtains the key in consumer custody and invokes the supplied writer once,
  synchronously in the calling owner process, with exactly 16 nonzero/non-FF
  octets. Return `:ok` only after that writer returns `:ok`; otherwise deny.
  No key is returned from the adapter or kept in request/result/owner state.
  The writer expires on callback return and cannot run from a foreign process,
  dispatch twice or select another command. An absent callback refuses rotation.
  Adapters must keep their private material and serial callback diagnostics out
  of logs, exception text and persisted host state. Transient host bytes are
  required for the UART write; this contract promises no secure memory erasure.

  A failed key-update send can still replace the local alternate key; a failed
  switch send can still schedule its activation. Basic responses identify no key.
  Independent physical sequence/counter and peer evidence remain required.

  Permit-join dispatch must finish by the horizon minus the requested duration.
  Migration dispatch reserves the qualified settling delay before the horizon;
  its observations must finish by the horizon itself. Key-update dispatch
  reserves distribution plus settling time; switch dispatch reserves settling
  time. Both reservations fit the shortened caller/custody/authorization budget.
  These host bounds do not prove the NCP's physical joining or switching time.
  The owner can shorten its deadline, never extend it. Adapters must return
  within the supplied budget; a blocking callback cannot be preempted. A late
  return cannot dispatch a new administrative command. Callback failures and
  private reason text become fixed public issues. Authorization does not
  prove secure enrollment, network continuity or physical joining state.
  """

  alias Wotex.Zigbee.{ChannelMigration, Error, KeyRotation, PermitJoin, Reply}
  alias Wotex.Zigbee.Network.Snapshot

  @derive {Inspect, only: [:module]}
  @enforce_keys [:module, :handle]
  defstruct @enforce_keys

  @type handle :: pid() | reference()
  @type t :: %__MODULE__{module: module(), handle: handle()}
  @type administration_context :: %{
          operation: :permit_join | :channel_migration,
          owner_epoch: reference(),
          request: PermitJoin.t() | ChannelMigration.t(),
          network: Snapshot.t(),
          now_ms: integer(),
          deadline_ms: integer()
        }

  @type rotation_context :: %{
          operation: :key_rotation,
          phase: :update | :switch,
          owner_epoch: reference(),
          request: KeyRotation.t(),
          network: Snapshot.t(),
          update: Reply.t() | nil,
          now_ms: integer(),
          deadline_ms: integer()
        }
  @type context :: administration_context() | rotation_context()

  @callback authorize(handle(), context(), pos_integer()) ::
              {:ok, integer()} | {:error, term()}

  @typedoc "A one-use, owner-process-only writer for transient private key bytes."
  @type key_writer :: (binary() -> :ok | {:error, Error.kind()})

  @doc "Obtains a private network key and invokes the supplied writer once within its budget."
  @callback with_network_key(handle(), rotation_context(), pos_integer(), key_writer()) ::
              :ok | {:error, term()}
  @optional_callbacks with_network_key: 4

  @doc "Builds an inert custody port using an explicit module and opaque consumer handle."
  @spec new(module(), handle()) :: {:ok, t()} | {:error, Error.t()}
  def new(module, handle) do
    port = %__MODULE__{module: module, handle: handle}

    if valid?(port),
      do: {:ok, port},
      else: {:error, %Error{kind: :invalid_value, operation: :credentials}}
  end

  @doc "Revalidates the exact port shape without loading a module or consulting its custody."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = port),
    do:
      map_size(port) == 3 and Map.has_key?(port, :module) and Map.has_key?(port, :handle) and
        is_atom(port.module) and port.module != nil and
        (is_pid(port.handle) or is_reference(port.handle))

  def valid?(_), do: false
end
