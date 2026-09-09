defmodule Wotex.BACnet.Client do
  @moduledoc """
  Defines the client port used for one explicitly configured BACnet session.

  A client implementation validates its own connection options in
  `c:connect/1`, performs one bounded native operation in `c:request/3`, and
  releases its session resources in `c:disconnect/1`. The opaque handle returned
  from `c:connect/1` is stored in `Wotex.BACnet.Session`. Custom handles remain
  opaque to the facade; first-party adapters use their known owner and deadline
  contracts. Optional callbacks expose sequential reads, explicit discovery,
  and finite Change of Value subscriptions.

  ## Consumer responsibility

  The consumer chooses the implementation and owns network configuration,
  credentials, trust policy, supervision, and any process lifetime beneath the
  handle. Custom callbacks are trusted executable code and must honor timeout
  and cleanup bounds themselves. Typed `Wotex.BACnet.Error` values retain their
  details when normalized; they must not expose credentials or unbounded
  peer output. Implementations must not add silent retries to write operations.
  """

  @doc "Opens a client handle using explicit configuration. No simulator fallback is allowed."
  @callback connect(keyword()) :: {:ok, term()} | {:error, term()}

  @doc "Executes a validated operation within a finite timeout, preserving protocol errors."
  @callback request(term(), map(), pos_integer()) :: {:ok, term()} | {:error, term()}

  @doc "Releases only resources owned by this handle; must be idempotent."
  @callback disconnect(term()) :: :ok | {:error, term()}
  @doc "Establishes a finite typed subscription within the supplied timeout."
  @callback subscribe(term(), Wotex.BACnet.COVRequest.t(), pid(), pos_integer()) ::
              {:ok, Wotex.BACnet.Subscription.t()} | {:error, term()}

  @doc "Cancels the original subscription and releases its owned listener and timers."
  @callback unsubscribe(term(), Wotex.BACnet.Subscription.t(), pos_integer()) ::
              :ok | {:error, term()}

  @doc "Reads an already normalized batch sequentially in one bounded operation slot."
  @callback read_properties(term(), [map()], pos_integer()) :: {:ok, map()} | {:error, term()}

  @doc "Collects a bounded observation window using an explicit configured Who-Is destination."
  @callback who_is(term(), non_neg_integer() | nil, non_neg_integer() | nil, pos_integer()) ::
              {:ok, [Wotex.BACnet.Device.t()]} | {:error, term()}

  @optional_callbacks subscribe: 4, unsubscribe: 3, read_properties: 3, who_is: 4
end
