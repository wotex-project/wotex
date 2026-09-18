defmodule Wotex.CoAP.Execution do
  @moduledoc """
  Supplies explicitly owned protocol time and identifiers for a connection.

  The default uses monotonic milliseconds, OTP timers and cryptographic tokens.
  An explicitly selected implementation can provide virtual time and a finite
  identifier script for deterministic fixtures. No environment or global process
  is consulted. Installed context is local to each explicitly started owner or
  transfer worker, and is inherited only by that owner's child work.
  """

  @typedoc """
  The execution context of an owner: the system default or an explicitly
  selected implementation with its own state.
  """
  @type context :: :system | {module(), term()}

  @doc "Returns the current protocol time in milliseconds for the given state."
  @callback now_ms(term()) :: integer()

  @doc """
  Schedules `event` to be delivered to `pid` after `delay` milliseconds and
  returns the timer reference.
  """
  @callback schedule(term(), pid(), term(), non_neg_integer()) :: reference()

  @doc """
  Cancels a scheduled timer and returns its remaining time, or `false` when it
  has already fired or is unknown.
  """
  @callback cancel(term(), reference()) :: non_neg_integer() | false

  @doc "Returns the initial CoAP message identifier for a new connection."
  @callback initial_mid(term()) :: 0..65_535

  @doc "Returns a fresh CoAP token."
  @callback token(term()) :: binary()

  @doc "Returns the message identifier to use, given the proposed next value."
  @callback message_id(term(), 0..65_535) :: 0..65_535

  @doc false
  @spec install(context()) :: :ok
  def install(context) do
    Process.put(:wotex_coap_execution, context)
    :ok
  end

  @doc false
  @spec context() :: context()
  def context, do: Process.get(:wotex_coap_execution, :system)

  @doc false
  @spec context(pid()) :: context()
  def context(pid) when is_pid(pid) and node(pid) == node() do
    case :erlang.process_info(pid, {:dictionary, :wotex_coap_execution}) do
      {{:dictionary, :wotex_coap_execution}, :system} -> :system
      {{:dictionary, :wotex_coap_execution}, {module, _} = context} when is_atom(module) -> context
      _ -> :system
    end
  end

  def context(_), do: :system

  @doc false
  @spec now_ms(context()) :: integer()
  def now_ms(context \\ context())
  def now_ms(:system), do: System.monotonic_time(:millisecond)
  def now_ms({module, value}), do: module.now_ms(value)

  @doc false
  @spec schedule(term(), non_neg_integer()) :: reference()
  def schedule(event, delay) do
    case context() do
      :system -> Process.send_after(self(), event, delay)
      {module, value} -> module.schedule(value, self(), event, delay)
    end
  end

  @doc false
  @spec cancel(reference()) :: non_neg_integer() | false
  def cancel(reference) do
    case context() do
      :system -> Process.cancel_timer(reference)
      {module, value} -> module.cancel(value, reference)
    end
  end

  @doc false
  @spec initial_mid() :: 0..65_535
  def initial_mid do
    case context() do
      :system ->
        <<mid::16>> = :crypto.strong_rand_bytes(2)
        mid

      {module, value} ->
        module.initial_mid(value)
    end
  end

  @doc false
  @spec message_id(0..65_535) :: 0..65_535
  def message_id(proposed) do
    case context() do
      :system -> proposed
      {module, value} -> module.message_id(value, proposed)
    end
  end

  @doc false
  @spec token() :: binary()
  def token do
    case context() do
      :system -> :crypto.strong_rand_bytes(8)
      {module, value} -> module.token(value)
    end
  end
end
