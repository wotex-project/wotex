defmodule Wotex.Runtime.Retry do
  @moduledoc """
  Pure retry classification for consumer retry loops.

  The classifier retries only transient failure classes and defaults to
  idempotent Property reads and Action queries. A consumer must opt an
  additional operation into retry with `idempotent?: true`, provide attempt
  counts, perform any delay, and execute the next call itself.

  This module never reads a clock, sleeps, schedules, or executes work.
  """

  @retryable_classes [:timeout, :unavailable, :rate_limited]
  @safe_operations [:readproperty, :queryaction]

  @type decision :: :stop | {:retry, non_neg_integer()}

  @doc "Returns a retry decision using explicit attempt and delay inputs."
  @spec decision(atom(), atom(), keyword()) :: decision()
  def decision(operation, failure_class, opts \\ []) when is_list(opts) do
    attempt = Keyword.get(opts, :attempt, 1)
    max_attempts = Keyword.get(opts, :max_attempts, 1)
    delay = Keyword.get(opts, :delay, 0)
    idempotent? = Keyword.get(opts, :idempotent?, operation in @safe_operations)

    if failure_class in @retryable_classes and idempotent? and is_integer(attempt) and
         is_integer(max_attempts) and attempt < max_attempts and is_integer(delay) and delay >= 0 do
      {:retry, delay}
    else
      :stop
    end
  end
end
