defmodule Wotex.Runtime.Retry do
  @moduledoc """
  Pure retry classification for consumer retry loops.

  The classifier retries only transient failure classes and defaults to
  idempotent Property reads and Action queries. A consumer must opt an
  additional operation into retry with `idempotent?: true`, provide attempt
  counts, perform any delay, and execute the next call itself.

  The failure class is either an explicit atom or a `Wotex.Runtime.Error`
  whose `class` field was populated from the transport's structured error.
  This module never reads a clock, sleeps, schedules, or executes work.
  """

  alias Wotex.Runtime.Error

  @retryable_classes [:timeout, :unavailable, :rate_limited]
  @safe_operations [:readproperty, :queryaction]

  @type decision :: :stop | {:retry, non_neg_integer()}

  @doc "Returns a retry decision using explicit attempt and delay inputs."
  @spec decision(atom(), atom() | Error.t(), keyword()) :: decision()
  def decision(operation, failure_class, opts \\ [])

  def decision(operation, %Error{} = error, opts), do: decision(operation, Error.class(error), opts)

  def decision(operation, failure_class, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      attempt = Keyword.get(opts, :attempt, 1)
      max_attempts = Keyword.get(opts, :max_attempts, 1)
      delay = Keyword.get(opts, :delay, 0)
      idempotent? = Keyword.get(opts, :idempotent?, operation in @safe_operations)

      if retry?(failure_class, idempotent?, attempt, max_attempts, delay) do
        {:retry, delay}
      else
        :stop
      end
    else
      :stop
    end
  end

  def decision(_operation, _failure_class, _opts), do: :stop

  defp retry?(failure_class, idempotent?, attempt, max_attempts, delay) do
    failure_class in @retryable_classes and idempotent? and is_integer(attempt) and
      is_integer(max_attempts) and attempt < max_attempts and is_integer(delay) and delay >= 0
  end
end
