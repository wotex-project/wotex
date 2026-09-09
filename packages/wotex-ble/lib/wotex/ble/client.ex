defmodule Wotex.BLE.Client do
  @moduledoc """
  Defines the client port for one explicitly configured BLE session.

  A client validates its options in `c:connect/1`, performs one bounded GATT
  operation in `c:request/3`, and releases its handle in `c:disconnect/1`. The
  handle is opaque to the facade and is stored in `Wotex.BLE.Session` together
  with the client module and request timeout.

  ## Consumer responsibility

  The consumer chooses the implementation, peer, credentials, trust policy and
  supervision. A persistent BlueZ client executes explicitly requested GATT
  discovery, pairing and connection lifecycle; custom clients define their own
  resource ownership within this callback contract. Implementations return tagged outcomes for normalization as
  `Wotex.BLE.Error`; raw operating-system errors, unbounded peer data, and
  credential material must not become public error details. A client must not
  silently retry an acknowledged write because the first attempt's effect may
  be unknown.
  """

  @doc "Opens a client handle using explicit configuration. No simulator fallback is allowed."
  @callback connect(keyword()) :: {:ok, term()} | {:error, term()}

  @doc "Executes a validated operation within a finite timeout, preserving protocol errors."
  @callback request(term(), map(), pos_integer()) :: {:ok, term()} | {:error, term()}

  @doc "Releases only resources owned by this handle; must be idempotent."
  @callback disconnect(term()) :: :ok | {:error, term()}
end
