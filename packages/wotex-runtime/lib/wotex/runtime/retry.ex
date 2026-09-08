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

  Only the Runtime operation vocabulary and four distinct options are admitted:
  `:attempt` and `:max_attempts` are positive integers, `:delay` is a non-negative
  integer, and `:idempotent?` is a boolean. Invalid or duplicate/unknown options
  stop rather than raising or authorizing a retry.
  """

  alias Wotex.Runtime.Error

  @retryable_classes [:timeout, :unavailable, :rate_limited]
  @safe_operations [:readproperty, :queryaction]
  @operations Wotex.Runtime.operations()
  @options [:attempt, :max_attempts, :delay, :idempotent?]

  @type decision :: :stop | {:retry, non_neg_integer()}

  @doc "Returns a retry decision using explicit attempt and delay inputs."
  @spec decision(atom(), atom() | Error.t(), keyword()) :: decision()
  def decision(operation, failure_class, opts \\ [])

  def decision(operation, %Error{} = error, opts), do: decision(operation, Error.class(error), opts)

  def decision(operation, failure_class, opts) when operation in @operations do
    case admit_options(opts, %{}) do
      {:ok, options} ->
        attempt = Map.get(options, :attempt, 1)
        max_attempts = Map.get(options, :max_attempts, 1)
        delay = Map.get(options, :delay, 0)
        idempotent? = Map.get(options, :idempotent?, operation in @safe_operations)

        if retry?(failure_class, idempotent?, attempt, max_attempts, delay) do
          {:retry, delay}
        else
          :stop
        end

      :error ->
        :stop
    end
  end

  def decision(_operation, _failure_class, _opts), do: :stop

  # Four distinct keys mean admission visits at most five list cells, including
  # the rejecting cell. Malformed and improper lists use the same stop path.
  defp admit_options([], options), do: {:ok, options}

  defp admit_options([{key, value} | rest], options)
       when key in @options and not is_map_key(options, key),
       do: admit_options(rest, Map.put(options, key, value))

  defp admit_options(_opts, _options), do: :error

  defp retry?(failure_class, true, attempt, max_attempts, delay)
       when failure_class in @retryable_classes and is_integer(attempt) and attempt > 0 and
              is_integer(max_attempts) and attempt < max_attempts and is_integer(delay) and
              delay >= 0,
       do: true

  defp retry?(_failure_class, _idempotent, _attempt, _max_attempts, _delay), do: false
end
