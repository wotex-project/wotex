defmodule Wotex.Thread.Address do
  @moduledoc """
  Validates the package's read-only OpenThread management request set.

  `validate_message/1` accepts a one-field map selecting `:state`, `:version`,
  `:network_name`, or `:rloc16`. Extra fields, state-changing commands, and
  application-level operations return `Wotex.Thread.Error`. The narrow shape
  prevents an arbitrary daemon command from crossing the client boundary.

  This module validates operation identity only. It does not select a Unix
  socket, query a daemon, authorize access, or assert that a node is attached to
  a Thread network. The accepted operations are consumed by
  `Wotex.Thread.Daemon` and may be produced by `Wotex.Thread.Mapping`. Dataset
  installation, commissioning, joiner workflows, and application Property or
  Action semantics remain outside this read-only profile.
  """
  alias Wotex.Thread.Error

  @doc "Allows only the explicit read-only daemon operation set."
  @spec validate_message(term()) :: :ok | {:error, Error.t()}
  def validate_message(%{type: type} = message)
      when map_size(message) == 1 and type in [:state, :version, :network_name, :rloc16],
      do: :ok

  def validate_message(_), do: {:error, Error.new(:unsupported_operation)}
end
