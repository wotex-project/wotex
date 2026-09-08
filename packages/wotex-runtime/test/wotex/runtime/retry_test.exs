defmodule Wotex.Runtime.RetryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Runtime.{Error, Retry}

  test "malformed, ambiguous and unknown retry options stop without raising" do
    base = [attempt: 1, max_attempts: 2]

    for value <- [nil, :yes, 1, "true", [], %{}] do
      assert Retry.decision(:readproperty, :timeout, base ++ [idempotent?: value]) == :stop
    end

    for opts <- [
          [attempt: -1, max_attempts: 2],
          [attempt: 0, max_attempts: 2],
          [attempt: 1, max_attempts: 0],
          [attempt: 1, max_attempts: 2, delay: -1],
          [attempt: 1, max_attempts: 2, delay: 0.5],
          [attempt: 1, max_attempts: 2, max_attempts: 0],
          [attempt: 1, max_attempts: 2, idempotent?: true, idempotent?: false],
          [attempt: 1, max_attempts: 2, unknown: true],
          [attempt: 1, max_attempts: "2"],
          [attempt: "1", max_attempts: 2],
          [:not_keyword],
          [{:attempt, 1} | :improper],
          %{},
          nil
        ] do
      assert Retry.decision(:readproperty, :timeout, opts) == :stop
    end
  end

  test "idempotence never admits an operation outside the Runtime vocabulary" do
    for operation <- [:unknown, nil, "readproperty", {:readproperty}, self()] do
      assert Retry.decision(operation, :timeout,
               idempotent?: true,
               attempt: 1,
               max_attempts: 2
             ) == :stop
    end
  end

  test "classified errors preserve the same finite retry budget and safe defaults" do
    error = %{Error.new(:transport_failed, :transport, "failed") | class: :timeout}

    for operation <- Wotex.Runtime.operations() do
      expected = if operation in [:readproperty, :queryaction], do: {:retry, 0}, else: :stop
      assert Retry.decision(operation, error, attempt: 1, max_attempts: 2) == expected
      assert Retry.decision(operation, error, attempt: 2, max_attempts: 2) == :stop
    end
  end

  test "the operation class idempotence and budget matrix authorizes only explicit valid retries" do
    for operation <- Wotex.Runtime.operations(),
        class <- [:timeout, :unavailable, :rate_limited, :permanent, :protocol],
        idempotent <- [true, false, nil],
        attempt <- [-1, 0, 1, 2, 3],
        maximum <- [-1, 0, 1, 2, 3],
        delay <- [-1, 0, 4] do
      expected =
        if class in [:timeout, :unavailable, :rate_limited] and idempotent == true and
             attempt > 0 and attempt < maximum and delay >= 0,
           do: {:retry, delay},
           else: :stop

      assert Retry.decision(operation, class,
               idempotent?: idempotent,
               attempt: attempt,
               max_attempts: maximum,
               delay: delay
             ) == expected
    end
  end
end
