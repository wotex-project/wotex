defmodule Wotex.Thread.NativeDatasetTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Thread
  alias Wotex.Thread.{Dataset, Error, OpenThread, State}
  alias Wotex.Thread.OpenThread.DatasetWire

  @moduletag :software
  @moduletag requirements: ["WTH-S01", "WTH-C03", "WTH-C07"], vectors: ["WTH-V02"]

  setup do
    assert match?({:unix, :linux}, :os.type())

    directory =
      Path.join(
        System.tmp_dir!(),
        "wth-dataset-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    executable = System.fetch_env!("WOTEX_THREAD_HOST")

    options = [
      client: OpenThread,
      executable: executable,
      executable_sha256: digest(executable),
      radio_url: "spinel+hdlc+forkpty://#{System.fetch_env!("WOTEX_THREAD_RCP")}?forkpty-arg=2",
      interface: "wthdataset",
      storage_path: Path.join(directory, "settings"),
      storage_mode: :create_new,
      owner: self(),
      timeout: 5000
    ]

    %{options: options}
  end

  defp digest(path),
    do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

  test "WTH-S01 WTH-V02 public native validation uses the SDK and leaves state unchanged",
       context do
    assert {:ok, session} = Thread.connect(context.options)
    active = dataset(:active)
    pending = dataset(:pending)
    assert :ok = Thread.validate_dataset(session, active, :active, 1000)
    assert :ok = Thread.validate_dataset(session, pending, :pending, 1000)

    assert {:error, %Error{code: :invalid_dataset}} =
             Thread.validate_dataset(session, pending, :active, 1000)

    assert {:error, %Error{code: :invalid_dataset}} =
             Thread.validate_dataset(session, active, :pending, 1000)

    bytes =
      active.entries
      |> Enum.reject(&(elem(&1, 0) == 4))
      |> encode_entries()

    {:ok, missing_pskc} = Dataset.decode(bytes)
    assert Dataset.complete?(missing_pskc, :active)

    assert {:error, %Error{code: :invalid_dataset}} =
             Thread.validate_dataset(session, missing_pskc, :active, 1000)

    assert {:error, %Error{code: :dataset_not_found}} = Thread.get_dataset(session, :active, 1000)
    assert {:error, %Error{code: :dataset_not_found}} = Thread.get_dataset(session, :pending, 1000)

    assert {:ok, %State{role: :disabled, ipv6_enabled: false, thread_enabled: false}} =
             Thread.inspect_state(session, [])

    assert {:error, %Error{code: :dataset_required, effect: :unknown}} =
             Thread.set_enabled(session, %{ipv6: true, thread: true}, 1000)

    assert {:ok, %State{ipv6_enabled: false, thread_enabled: false}} =
             Thread.inspect_state(session, [])

    assert {:ok, %State{ipv6_enabled: true, thread_enabled: false}} =
             Thread.set_enabled(session, %{ipv6: true, thread: false}, 1000)

    assert {:ok, %State{ipv6_enabled: false, thread_enabled: false}} =
             Thread.set_enabled(session, %{ipv6: false, thread: false}, 1000)

    assert :ok = Thread.disconnect(session)
    refute File.exists?("/sys/class/net/wthdataset")
  end

  test "WTH-S01 WTH-V02 explicit export reads credentials written by the real SDK fixture",
       context do
    seed(context.options)
    options = Keyword.put(context.options, :storage_mode, :open_existing)
    assert {:ok, session} = Thread.connect(options)
    active = dataset(:active)
    assert {:ok, ^active} = Thread.get_dataset(session, :active, 1000)
    assert {:ok, pending} = Thread.get_dataset(session, :pending, 1000)
    assert {250, "unknown"} in pending.entries
    assert :ok = Thread.validate_dataset(session, pending, :pending, 1000)
    refute inspect(pending) =~ "fedcba"
    refute inspect(:sys.get_status(session.handle.pid)) =~ "fedcba"

    assert {:ok, %State{ipv6_enabled: true, thread_enabled: true}} =
             Thread.set_enabled(session, %{ipv6: true, thread: true}, 1000)

    assert {:ok, %State{ipv6_enabled: true, thread_enabled: true}} =
             Thread.set_enabled(session, %{ipv6: true, thread: true}, 1000)

    assert {:ok, %State{ipv6_enabled: false, thread_enabled: false}} =
             Thread.set_enabled(session, %{ipv6: false, thread: false}, 1000)

    assert {:ok, ^active} = Thread.get_dataset(session, :active, 1000)
    assert :ok = Thread.disconnect(session)
    refute File.exists?("/sys/class/net/wthdataset")
  end

  @tag requirements: ["WTH-S04", "WTH-C03", "WTH-C04"], vectors: ["WTH-V05"]
  test "explicit formation waits for a real SDK leader and refuses to overwrite its Dataset",
       context do
    options = Keyword.put(context.options, :allow_network_creation, true)
    assert {:ok, session} = Thread.connect(options)
    active = dataset(:active)

    assert {:ok, %State{role: :leader, ipv6_enabled: true, thread_enabled: true}} =
             Thread.form_network(session, active, 30_000)

    assert {:ok, ^active} = Thread.get_dataset(session, :active, 1000)

    assert {:ok, %State{role: :disabled}} =
             Thread.set_enabled(session, %{ipv6: false, thread: false}, 1000)

    assert {:error,
            %Error{
              code: :dataset_exists,
              effect: :unknown,
              details: %{state: %State{role: :disabled}}
            }} = Thread.form_network(session, active, 1000)

    assert {:ok, ^active} = Thread.get_dataset(session, :active, 1000)
    assert :ok = Thread.disconnect(session)
    refute File.exists?("/sys/class/net/wthdataset")
  end

  @tag requirements: ["WTH-S04", "WTH-C04"], vectors: ["WTH-V06"]
  test "real management callbacks separate acceptance, rejection and pending effectiveness",
       context do
    assert {:ok, session} =
             Thread.connect(Keyword.put(context.options, :allow_network_creation, true))

    active = dataset(:active)
    assert {:ok, %State{role: :leader}} = Thread.form_network(session, active, 30_000)
    updated = timestamp(active, 2)

    assert {:ok, %{accepted: true, effective: :not_verified}} =
             Thread.management_active_set(session, %{dataset: updated}, 5000)

    assert {:ok, ^updated} = Thread.get_dataset(session, :active, 1000)

    assert {:error, %Error{code: :remote_error, effect: :unknown, details: %{status: 37}}} =
             Thread.management_active_set(session, %{dataset: active}, 5000)

    assert {:ok, %{accepted: true, effective: :not_verified}} =
             Thread.management_pending_set(
               session,
               %{dataset: timestamp(dataset(:pending), 3)},
               5000
             )

    assert {:ok, ^updated} = Thread.get_dataset(session, :active, 1000)
    assert {:ok, pending} = Thread.get_dataset(session, :pending, 1000)
    assert {14, <<3::48, 0::16>>} in pending.entries
    assert :ok = Thread.disconnect(session)
    refute File.exists?("/sys/class/net/wthdataset")
  end

  @tag requirements: ["WTH-S05", "WTH-C03", "WTH-C04"], vectors: ["WTH-V08"]
  test "owned commissioner activates and admits only exact finite joiner records", context do
    assert {:ok, session} =
             Thread.connect(Keyword.put(context.options, :allow_network_creation, true))

    assert {:ok, %State{role: :leader}} = Thread.form_network(session, dataset(:active), 30_000)
    assert {:ok, %{state: :active}} = Thread.commissioner_start(session, timeout: 5000)

    for input <- [%{eui64: <<42::64>>}, %{discerner: %{length: 64, value: 42}}] do
      {:ok, identity} = Wotex.Thread.JoinerIdentity.new(input)

      {:ok, admission} =
        Wotex.Thread.JoinerAdmission.new(%{identity: identity, pskd: "WTEST123", lifetime: 1})

      assert {:ok, %{identity: ^input, lifetime_s: 1}} = Thread.add_joiner(session, admission, 1000)
      assert :ok = Thread.remove_joiner(session, identity, 1000)

      assert {:error, %Error{code: :remote_error, effect: :unknown, details: %{status: 23}}} =
               Thread.remove_joiner(session, identity, 1000)
    end

    assert {:ok, %{state: :disabled}} = Thread.commissioner_stop(session, timeout: 1000)
    assert {:ok, %{state: :disabled}} = Thread.commissioner_stop(session, timeout: 1000)
    assert :ok = Thread.disconnect(session)
    refute File.exists?("/sys/class/net/wthdataset")
  end

  defp timestamp(dataset, seconds) do
    entries =
      Enum.map(dataset.entries, fn
        {14, _} -> {14, <<seconds::48, 0::16>>}
        entry -> entry
      end)

    {:ok, value} = Dataset.decode(encode_entries(entries))
    value
  end

  defp dataset(kind) do
    entries = [
      {0, <<0, 0, 15>>},
      {1, <<0x12, 0x34>>},
      {2, <<1, 2, 3, 4, 5, 6, 7, 8>>},
      {3, "wotex-sdk"},
      {4, "0123456789abcdef"},
      {5, "fedcba9876543210"},
      {7, <<0xFD, 1, 2, 3, 4, 5, 6, 7>>},
      {12, <<2, 0xA0, 0xF7, 0xF8>>},
      {14, <<1::48, 0::16>>},
      {53, <<0, 4, 0, 0x1F, 0xFF, 0xE0>>},
      {250, "unknown"}
    ]

    entries =
      if kind == :pending,
        do: entries ++ [{51, <<1::48, 0::16>>}, {52, <<300_000::32>>}],
        else: entries

    {:ok, dataset} =
      entries
      |> encode_entries()
      |> Dataset.decode()

    dataset
  end

  defp encode_entries(entries),
    do: for({type, value} <- entries, into: <<>>, do: <<type, byte_size(value), value::binary>>)

  defp seed(options) do
    config =
      options
      |> Keyword.take([:radio_url, :interface, :storage_path])
      |> Map.new()

    config = Map.merge(config, %{storage_mode: "create_new", allow_network_creation: false})
    {:ok, %{dataset: active}} = DatasetWire.parameters(dataset(:active), :active)
    {:ok, %{dataset: pending}} = DatasetWire.parameters(dataset(:pending), :pending)
    executable = System.fetch_env!("WOTEX_THREAD_DATASET_SEED")

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        env: Enum.map(System.get_env(), fn {key, _} -> {String.to_charlist(key), false} end)
      ])

    try do
      assert Port.command(
               port,
               Jason.encode!(%{config: config, active: active, pending: pending}) <> "\n"
             )

      receive do
        {^port, {:exit_status, status}} -> assert status == 0
        {^port, {:data, _}} -> flunk("SDK fixture emitted unexpected diagnostic output")
      after
        5000 -> flunk("SDK fixture did not finish within its deadline")
      end
    after
      try do
        Port.close(port)
      rescue
        ArgumentError -> :ok
      end
    end
  end
end
