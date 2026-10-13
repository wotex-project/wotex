defmodule Wotex.Routines.DriverHost do
  @moduledoc """
  Consumer-owned wakeup processing boundary.

  The host obtains fresh complete active membership, facts and caller-owned
  time, evaluates inert transitions and atomically rechecks authors/grants,
  program/proof identities, revisions, constraints, capacity and root accounting.
  It persists originals and held/refused outcomes together. Claim and final
  handoff repeat mutable guards; transport begins only after the durable marker.
  Restart, timeout, cancellation and restore retain no-repeat/unknown history.

  A wakeup cause supplies no original or permission. Returning :ok only reports
  processing completion; an unconditional-success host does not meet the
  transaction contract. Work must fit the explicit budget. The host owns any
  subprocesses, native containment, clock qualification and physical evidence.
  """

  @type cause :: :manual | :basis_changed | :poll
  @type budget :: %{work_timeout_ms: pos_integer()}
  @callback wakeup(term(), cause(), budget()) :: :ok | {:error, atom()}
end
