Code.require_file("../support/software/resources.exs", __DIR__)

defmodule Wotex.Matter.NativeOneshotStressTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Matter
  alias Wotex.Matter.{AttributeReport, Error, Native, SoftwareResources}
  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 900_000

  test "read-only one-shot load releases its controller after each operation" do
    assert File.dir?("/proc/self/fd"), "the native process census requires Linux procfs"

    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_ONESHOT_STRESS_FIXTURE")
      |> File.read!()
      |> Jason.decode!()

    SoftwareResources.with_probe(
      fixture["resource_directory"],
      %{"process_directory" => true},
      fn probe ->
        stress(fixture, probe)
      end
    )
  end

  defp stress(fixture, probe) do
    controller = Map.fetch!(fixture, "controller")

    config =
      [
        client: Native,
        lifecycle: :oneshot,
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

    address = %{
      fabric_id: config[:fabric_id],
      node_id: fixture["node_id"],
      endpoint: Map.fetch!(fixture, "endpoint"),
      cluster: 6,
      member: 0
    }

    {:ok, session} = Matter.connect(config)
    ports = owned_ports(config[:executable])
    assert ports == []
    assert {:ok, %AttributeReport{value: value}} = Matter.read_attribute(session, address)
    assert cleaned?(config[:executable], probe, 100)
    {generations, %{success: 1}} = SoftwareResources.closed_generations!(probe, MapSet.new(), 1)

    {samples, generations} =
      Enum.map_reduce(1..10, generations, fn batch, generations ->
        generations =
          Enum.reduce(1..100, generations, fn _, previous ->
            assert {:ok, %AttributeReport{value: ^value}} = Matter.read_attribute(session, address)
            assert cleaned?(config[:executable], probe, 100)
            {next, %{success: 1}} = SoftwareResources.closed_generations!(probe, previous, 1)
            next
          end)

        {:memory, bytes} = Process.info(self(), :memory)
        {%{completed: batch * 100, caller_heap_bytes: bytes}, generations}
      end)

    generations =
      Enum.reduce(1..100, generations, fn _, previous ->
        assert {:ok, one} = Matter.connect(config)
        assert {:ok, %AttributeReport{value: ^value}} = Matter.read_attribute(one, address)
        assert :ok = Matter.disconnect(one)
        assert cleaned?(config[:executable], probe, 100)
        {next, %{success: 1}} = SoftwareResources.closed_generations!(probe, previous, 1)
        next
      end)

    results =
      1..32
      |> Task.async_stream(fn _ -> Matter.read_attribute(session, address) end,
        max_concurrency: 32,
        timeout: 15_000,
        ordered: false
      )
      |> Enum.to_list()

    counts =
      Enum.frequencies_by(results, fn
        {:ok, {:ok, %AttributeReport{value: ^value}}} -> :success
        {:ok, {:error, %Error{code: code}}} -> code
        other -> raise "unexpected concurrent return: #{inspect(other)}"
      end)

    assert Enum.sum(Map.values(counts)) == 32
    assert Map.get(counts, :success, 0) > 0
    assert Map.keys(counts) -- [:success, :storage_open_failed] == []
    assert cleaned?(config[:executable], probe, 100)
    {generations, native_outcomes} = SoftwareResources.closed_generations!(probe, generations, 32)
    assert native_outcomes == counts
    assert MapSet.size(generations) == 1133
    assert :ok = Matter.disconnect(session)

    File.write!(
      Map.fetch!(fixture, "result_path"),
      Jason.encode!(%{
        status: "passed",
        sequential_operations: 1000,
        open_close_cycles: 100,
        concurrent_callers: 32,
        native_generations_observed: MapSet.size(generations),
        outcomes: counts,
        samples: samples,
        owned_ports_after_cleanup: 0,
        owned_native_children_after_cleanup: 0
      }),
      [:exclusive]
    )
  end

  defp owned_ports(executable) do
    Enum.filter(Port.list(), &(Port.info(&1, :name) == {:name, String.to_charlist(executable)}))
  end

  defp cleaned?(_, _, 0), do: false

  defp cleaned?(executable, probe, remaining) do
    if owned_ports(executable) == [] and children(probe) == [] do
      true
    else
      Process.sleep(10)
      cleaned?(executable, probe, remaining - 1)
    end
  end

  defp children(probe) do
    for name <- File.ls!(probe),
        [_, child] <- [Regex.run(~r/^process-([1-9][0-9]*)$/, name)],
        File.exists?("/proc/" <> child),
        do: child
  end
end
