defmodule WotexLabWorkbench.ControlLimitsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.Control.{Ledger, Limits}

  test "configuration fills defaults and refuses unknown, duplicate or unbounded limits" do
    assert {:ok, defaults} = Limits.configure([])

    assert defaults == [
             max_requests: 30,
             window_ms: 60_000,
             session_concurrency: 1,
             host_concurrency: 8,
             origins: []
           ]

    assert {:ok, custom} = Limits.configure(origins: ["https://client.example:8443"])
    assert custom[:origins] == ["https://client.example:8443"]

    for invalid <- [
          [caller: 1],
          [max_requests: 1, max_requests: 2],
          [max_requests: 0],
          [window_ms: 99],
          [session_concurrency: 9],
          [host_concurrency: 65],
          [session_concurrency: 4, host_concurrency: 2],
          [origins: ["https://client.example/path"]],
          [origins: "https://client.example"],
          [origins: for(index <- 1..9, do: "https://client-#{index}.example")],
          ["max_requests"],
          :enabled
        ] do
      assert {:error, %Error{code: :invalid_control_limits}} = Limits.configure(invalid)
    end

    assert {:error, %Error{code: :invalid_control_limits}} =
             Limits.start_link(name: __MODULE__.Invalid, max_requests: 0)
  end

  test "slots are released explicitly or when the request process exits" do
    limits =
      start_supervised!(
        {Limits,
         name: __MODULE__.Slots,
         session_concurrency: 1,
         host_concurrency: 2,
         origins: ["http://127.0.0.1:4000"]}
      )

    assert Limits.origins(limits) == ["http://127.0.0.1:4000"]
    assert {:ok, slot} = Limits.acquire(limits, "session-a")

    assert {:error, %Error{code: :concurrency_limited}} = Limits.acquire(limits, "session-a")
    assert :ok = Limits.release(limits, slot)
    assert :ok = Limits.release(limits, slot)
    assert {:ok, _} = Limits.acquire(limits, "session-a")

    parent = self()

    holder =
      spawn(fn ->
        {:ok, _} = Limits.acquire(limits, "session-b")
        send(parent, :held)

        receive do
          :stop -> :ok
        end
      end)

    assert_receive :held
    assert {:error, %Error{code: :concurrency_limited}} = Limits.acquire(limits, "session-c")
    monitor = Process.monitor(holder)
    send(holder, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^holder, _reason}
    eventually(fn -> :sys.get_state(limits).in_flight == 1 end)
    assert {:ok, _} = Limits.acquire(limits, "session-c")
  end

  test "the fixed admission window resets and discards idle sessions" do
    limits =
      start_supervised!({Limits, name: __MODULE__.Window, max_requests: 2, window_ms: 100})

    assert {:ok, first} = Limits.acquire(limits, "session-a")
    :ok = Limits.release(limits, first)
    assert {:ok, second} = Limits.acquire(limits, "session-a")
    :ok = Limits.release(limits, second)

    assert {:error, %Error{code: :rate_limited, details: %{retry_after_ms: retry}}} =
             Limits.acquire(limits, "session-a")

    assert retry in 1..100
    Process.sleep(retry + 5)
    assert {:ok, third} = Limits.acquire(limits, "session-b")
    :ok = Limits.release(limits, third)
    assert Map.keys(:sys.get_state(limits).sessions) == ["session-b"]
    assert {:ok, _} = Limits.acquire(limits, "session-a")
  end

  test "the ledger replays identical fingerprints and never evicts identities" do
    ledger = Ledger.new()
    assert Ledger.check(ledger, "key", "a") == :new
    ledger = Ledger.retain(ledger, "key", "a", {:ok, "run-1"})
    assert Ledger.check(ledger, "key", "a") == {:replay, {:ok, "run-1"}}
    assert {:error, %Error{code: :idempotency_key_reused}} = Ledger.check(ledger, "key", "b")

    full =
      Enum.reduce(2..Ledger.capacity(), ledger, fn index, acc ->
        Ledger.retain(acc, "key-#{index}", "a", {:error, Error.new(:refused, :room, "refused")})
      end)

    assert map_size(full) == Ledger.capacity()
    assert {:error, %Error{code: :idempotency_capacity}} = Ledger.check(full, "fresh", "a")
    assert {:replay, {:error, %Error{code: :refused}}} = Ledger.check(full, "key-2", "a")
  end

  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() ->
        :ok

      attempts == 0 ->
        flunk("condition did not become true")

      true ->
        Process.sleep(10)
        eventually(fun, attempts - 1)
    end
  end
end
