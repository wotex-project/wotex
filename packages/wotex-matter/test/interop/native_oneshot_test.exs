defmodule Wotex.Matter.NativeOneshotInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter
  alias Wotex.Matter.{AttributeReport, Native, RuntimeCredentials, Transport}
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, Result}

  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 180_000
  @empty %{tag: :anonymous, type: :structure, value: []}

  test "native one-shot operations preserve typed API and scalar Runtime results with no retained child" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_ONESHOT_FIXTURE")
      |> File.read!()
      |> Jason.decode!()

    controller = Map.fetch!(fixture, "controller")

    config =
      [
        client: Native,
        lifecycle: :persistent,
        storage_mode: :open_existing,
        authority: :stored,
        timeout: 10_000
      ] ++
        Enum.map(
          [
            :executable,
            :storage_path,
            :vendor_id,
            :fabric_id,
            :controller_node_id,
            :paa_trust_store
          ],
          &{&1, Map.fetch!(controller, Atom.to_string(&1))}
        )

    baseline = MapSet.new(Port.list())
    assert native_children(config[:executable]) == []
    node = %{fabric_id: config[:fabric_id], node_id: Map.fetch!(fixture, "node_id")}
    assert {:ok, persistent} = Matter.connect(config)

    endpoint =
      try do
        assert {:ok, catalogue} = Matter.discover_endpoints(persistent, node)

        [entry] =
          Enum.filter(catalogue.endpoints, fn entry ->
            match?({:ok, _}, entry.server_clusters) and
              Enum.all?([0x0201, 6], &(&1 in elem(entry.server_clusters, 1).value))
          end)

        entry.endpoint
      after
        assert :ok = Matter.disconnect(persistent)
      end

    assert cleaned?(config[:executable], baseline, 100)

    config = Keyword.put(config, :lifecycle, :oneshot)
    assert {:ok, session} = Matter.connect(config)
    assert cleaned?(config[:executable], baseline, 100)
    on = Map.merge(node, %{endpoint: endpoint, cluster: 6, member: 0})
    heating = %{on | cluster: 0x0201, member: 0x0012}

    assert {:ok, %AttributeReport{value: original}} = Matter.read_attribute(session, heating)
    assert cleaned?(config[:executable], baseline, 100)
    changed = %{original | value: if(original.value == 2100, do: 2050, else: 2100)}
    assert {:ok, %{status: 0}} = Matter.write_attribute(session, heating, changed)
    assert cleaned?(config[:executable], baseline, 100)
    assert {:ok, %AttributeReport{value: ^changed}} = Matter.read_attribute(session, heating)
    assert cleaned?(config[:executable], baseline, 100)
    assert {:ok, %{status: 0, value: nil}} = Matter.invoke_command(session, on, @empty)
    assert cleaned?(config[:executable], baseline, 100)

    assert {:ok, %AttributeReport{value: %{type: :boolean, value: false}}} =
             Matter.read_attribute(session, on)

    assert cleaned?(config[:executable], baseline, 100)

    consumed = consumed(config, on, heating)

    assert {:ok, %Result{payload: false, metadata: %{}}} =
             ConsumedThing.read_property(consumed, "on", context("oneshot-read"))

    assert cleaned?(config[:executable], baseline, 100)

    assert {:ok, %Result{payload: "written", metadata: %{}}} =
             ConsumedThing.write_property(
               consumed,
               "heating",
               original.value,
               context("oneshot-write")
             )

    assert cleaned?(config[:executable], baseline, 100)

    assert {:ok, %Result{payload: value}} =
             ConsumedThing.read_property(consumed, "heating", context("oneshot-readback"))

    assert value == original.value
    assert cleaned?(config[:executable], baseline, 100)

    assert {:ok, %Result{payload: nil}} =
             ConsumedThing.invoke_action(consumed, "on", %{}, context("oneshot-on"))

    assert cleaned?(config[:executable], baseline, 100)

    assert {:ok, %Result{payload: true}} =
             ConsumedThing.read_property(consumed, "on", context("oneshot-on-readback"))

    assert cleaned?(config[:executable], baseline, 100)

    assert {:ok, %Result{payload: nil}} =
             ConsumedThing.invoke_action(consumed, "off", %{}, context("oneshot-off"))

    assert cleaned?(config[:executable], baseline, 100)
    assert :ok = Matter.disconnect(session)

    File.write!(
      Map.fetch!(fixture, "result_path"),
      Jason.encode!(%{
        status: "passed",
        endpoint: endpoint,
        native_operations: 5,
        runtime_operations: 6,
        owned_ports_after_cleanup: 0,
        native_processes_after_cleanup: 0
      }),
      [:exclusive]
    )
  end

  defp consumed(config, on, heating) do
    assert {:ok, td} =
             Wotex.ThingDescription.from_map(%{
               "@context" => "https://www.w3.org/2022/wot/td/v1.1",
               "id" => "urn:example:matter:native-oneshot",
               "title" => "Native one-shot fixture",
               "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
               "security" => ["none"],
               "properties" => %{
                 "on" => %{
                   "readOnly" => true,
                   "forms" => [%{"href" => href(on), "op" => "readproperty"}]
                 },
                 "heating" => %{
                   "forms" => [
                     %{"href" => href(heating), "op" => ["readproperty", "writeproperty"]}
                   ]
                 }
               },
               "actions" => %{
                 "on" => %{
                   "forms" => [%{"href" => href(%{on | member: 1}), "op" => "invokeaction"}]
                 },
                 "off" => %{"forms" => [%{"href" => href(on), "op" => "invokeaction"}]}
               }
             })

    assert {:ok, profile} = Matter.profile(:oneshot)

    assert {:ok, consumed} =
             ConsumedThing.new(td,
               profiles: [profile],
               transports: %{
                 BindingProfile.id(profile) =>
                   {Transport, Keyword.put(config, :target, Integer.to_string(on.fabric_id))}
               },
               credentials: {RuntimeCredentials, %{test_pid: self()}}
             )

    consumed
  end

  defp href(path),
    do: "matter://#{path.fabric_id}/#{path.node_id}/#{path.endpoint}/#{path.cluster}/#{path.member}"

  defp context(id) do
    assert {:ok, context} =
             Context.new(request_id: id, deadline: System.monotonic_time(:millisecond) + 10_000)

    context
  end

  defp cleaned?(_, _, 0), do: false

  defp cleaned?(executable, baseline, remaining) do
    if MapSet.new(Port.list()) == baseline and native_children(executable) == [] do
      true
    else
      Process.sleep(10)
      cleaned?(executable, baseline, remaining - 1)
    end
  end

  defp native_children(executable) do
    assert File.dir?("/proc/self")

    for path <- Path.wildcard("/proc/[0-9]*/cmdline"),
        {:ok, bytes} <- [File.read(path)],
        [^executable | _] <- [String.split(bytes, <<0>>, trim: true)],
        do:
          path
          |> Path.dirname()
          |> Path.basename()
          |> String.to_integer()
  end
end
