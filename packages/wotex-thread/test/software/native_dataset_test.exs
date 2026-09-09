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

    options = [
      client: OpenThread,
      executable: System.fetch_env!("WOTEX_THREAD_HOST"),
      radio_url: "spinel+hdlc+forkpty://#{System.fetch_env!("WOTEX_THREAD_RCP")}?forkpty-arg=2",
      interface: "wthdataset",
      storage_path: Path.join(directory, "settings"),
      storage_mode: :create_new,
      owner: self(),
      timeout: 5000
    ]

    %{options: options}
  end

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
      if Port.info(port), do: Port.close(port)
    end
  end
end
