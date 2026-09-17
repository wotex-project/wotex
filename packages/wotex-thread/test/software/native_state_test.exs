defmodule Wotex.Thread.NativeStateTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Thread
  alias Wotex.Thread.{Dataset, Error, OpenThread, State}

  @moduletag :software
  @moduletag requirements: ["WTH-S06", "WTH-C05", "WTH-B02"], vectors: ["WTH-V10"]
  @role_flag 4

  setup do
    assert match?({:unix, :linux}, :os.type())

    directory =
      Path.join(
        System.tmp_dir!(),
        "wth-state-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    options = [
      client: OpenThread,
      executable: System.fetch_env!("WOTEX_THREAD_HOST"),
      radio_url: "spinel+hdlc+forkpty://#{System.fetch_env!("WOTEX_THREAD_RCP")}?forkpty-arg=24",
      interface: "wthstate",
      storage_path: Path.join(directory, "settings"),
      storage_mode: :create_new,
      allow_network_creation: true,
      owner: self(),
      # Sanitizer-host startup under a concurrent lane can exceed the 5000 ms default.
      timeout: 10_000
    ]

    %{options: options}
  end

  test "WTH-S06 WTH-V10 real SDK role changes arrive as bounded non-secret snapshots", context do
    assert {:ok, session} = Thread.connect(context.options)
    assert {:ok, first} = Thread.subscribe(session, %{type: :state})
    assert {:ok, second} = Thread.subscribe(session, %{type: :state, max_queue_length: 64})
    assert second.generation == first.generation + 1

    for subscription <- [first, second] do
      reference = subscription.reference

      assert_receive {:wotex_thread, ^reference,
                      {:ok, %State{role: :disabled}, %{changed_flags: 0}}},
                     2000
    end

    assert {:ok, %State{role: :leader}} = Thread.form_network(session, dataset(), 30_000)
    roles = collect(first.reference, :leader, [])
    assert List.last(roles) == :leader

    # Every report carries the SDK role flag or other numeric flags; no secret fields exist.
    assert Enum.all?(roles, &(&1 in [:disabled, :detached, :child, :router, :leader]))

    # The first stream is cancelled; the second still receives the following disable transition.
    assert :ok = Thread.unsubscribe(session, first)

    assert {:ok, %State{role: :disabled}} =
             Thread.set_enabled(session, %{ipv6: false, thread: false}, 1000)

    reference = second.reference
    assert collect(reference, :disabled, []) |> List.last() == :disabled
    first_reference = first.reference
    refute_receive {:wotex_thread, ^first_reference, _}, 200
    assert :ok = Thread.unsubscribe(session, second)
    assert :ok = Thread.disconnect(session)
  end

  test "WTH-C05 receiver death and session close release real SDK stream owners", context do
    assert {:ok, session} = Thread.connect(context.options)
    receiver = spawn(fn -> Process.sleep(:infinity) end)
    assert {:ok, orphaned} = Thread.subscribe(session, %{type: :state, receiver: receiver})
    assert {:ok, live} = Thread.subscribe(session, %{type: :state})
    Process.exit(receiver, :kill)
    eventually(fn -> map_size(:sys.get_state(session.handle.pid).subscriptions) == 1 end)
    assert :ok = Thread.unsubscribe(session, orphaned)
    [record] = Map.values(:sys.get_state(session.handle.pid).subscriptions)
    owner = Process.monitor(record.owner)
    assert :ok = Thread.disconnect(session)
    reference = live.reference
    assert_receive {:wotex_thread, ^reference, {:error, %Error{code: :connection_closed}}}, 2000
    assert_receive {:DOWN, ^owner, :process, _, _}, 2000
  end

  defp collect(reference, target, roles) do
    receive do
      {:wotex_thread, ^reference, {:ok, %State{role: role}, %{changed_flags: flags}}} ->
        assert is_integer(flags) and flags > 0
        roles = roles ++ [role]

        if role == target and Bitwise.band(flags, @role_flag) != 0,
          do: roles,
          else: collect(reference, target, roles)
    after
      30_000 -> flunk("no #{target} State report; observed #{inspect(roles)}")
    end
  end

  defp dataset do
    entries = [
      {0, <<0, 0, 15>>},
      {1, <<0x12, 0x35>>},
      {2, <<1, 2, 3, 4, 5, 6, 7, 9>>},
      {3, "wotex-state"},
      {4, "0123456789abcdef"},
      {5, "fedcba9876543210"},
      {7, <<0xFD, 1, 2, 3, 4, 5, 6, 8>>},
      {12, <<2, 0xA0, 0xF7, 0xF8>>},
      {14, <<1::48, 0::16>>},
      {53, <<0, 4, 0, 0x1F, 0xFF, 0xE0>>}
    ]

    {:ok, dataset} =
      Dataset.decode(
        for {type, value} <- entries, into: <<>>, do: <<type, byte_size(value), value::binary>>
      )

    dataset
  end

  defp eventually(condition, remaining \\ 200)
  defp eventually(condition, 0), do: assert(condition.())

  defp eventually(condition, remaining) do
    unless condition.() do
      Process.sleep(10)
      eventually(condition, remaining - 1)
    end
  end
end
