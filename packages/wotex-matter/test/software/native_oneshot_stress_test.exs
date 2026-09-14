defmodule Wotex.Matter.NativeOneshotStressTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Matter
  alias Wotex.Matter.{AttributeReport, Error, Native}
  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 900_000

  test "read-only one-shot load releases its controller after each operation" do
    assert File.dir?("/proc/self/fd"), "the native process census requires Linux procfs"

    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_ONESHOT_STRESS_FIXTURE")
      |> File.read!()
      |> Jason.decode!()

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
    assert cleaned?(config[:executable], 100)

    samples =
      for batch <- 1..10 do
        for _ <- 1..100 do
          assert {:ok, %AttributeReport{value: ^value}} = Matter.read_attribute(session, address)
          assert cleaned?(config[:executable], 100)
        end

        {:memory, bytes} = Process.info(self(), :memory)
        %{completed: batch * 100, caller_heap_bytes: bytes}
      end

    for _ <- 1..100 do
      assert {:ok, one} = Matter.connect(config)
      assert {:ok, %AttributeReport{value: ^value}} = Matter.read_attribute(one, address)
      assert :ok = Matter.disconnect(one)
      assert cleaned?(config[:executable], 100)
    end

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

    IO.inspect(counts, label: "concurrent outcomes")
    assert Enum.sum(Map.values(counts)) == 32
    assert Map.get(counts, :success, 0) > 0
    assert Map.keys(counts) -- [:success, :storage_open_failed] == []
    assert cleaned?(config[:executable], 100)
    assert :ok = Matter.disconnect(session)

    File.write!(
      Map.fetch!(fixture, "result_path"),
      Jason.encode!(%{
        status: "passed",
        sequential_operations: 1000,
        open_close_cycles: 100,
        concurrent_callers: 32,
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

  defp cleaned?(_, 0), do: false

  defp cleaned?(executable, remaining) do
    if owned_ports(executable) == [] and children(executable) == [] do
      true
    else
      Process.sleep(10)
      cleaned?(executable, remaining - 1)
    end
  end

  defp children(executable) do
    for path <- Path.wildcard("/proc/[0-9]*/cmdline"),
        {:ok, bytes} <- [File.read(path)],
        [^executable | _] <- [String.split(bytes, <<0>>, trim: true)],
        do: path
  end
end
