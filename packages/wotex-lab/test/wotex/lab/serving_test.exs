defmodule Wotex.Lab.ServingTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab
  alias Wotex.Lab.Examples.Thermal
  alias Wotex.Lab.Test.BlockingServing
  alias Wotex.Nx.Encoded

  @moduletag capture_log: true

  test "inline and supervised Serving preserve padding, keys, timeout flush and callers" do
    assert {:ok, thermal} = Thermal.run()
    batch = Encoded.batch(thermal.encoded)

    row_target = fn {{values}, {masks}, _} ->
      Nx.add(Nx.multiply(values, Nx.as_type(masks, Nx.type(values))), 1.0)
    end

    serving = Nx.Serving.jit(row_target, compiler: Nx.Defn.Evaluator)
    inline = Nx.Serving.run(serving, batch)
    assert Nx.to_flat_list(inline) == [21.0, 23.0]

    {:ok, lab} = Lab.start_link(id: "serving-test", max_children: 1)
    name = :wotex_lab_serving_test

    {:ok, serving_pid} =
      Lab.start_child(
        lab,
        :sessions,
        {Nx.Serving,
         serving: serving,
         name: name,
         batch_size: 4,
         batch_timeout: 10,
         batch_keys: [:default, :room_a]}
      )

    assert Nx.to_flat_list(Nx.Serving.batched_run(name, batch)) == [21.0, 23.0]

    padded = Nx.Batch.pad(batch, 2)
    assert padded.pad == 2
    assert Nx.to_flat_list(Nx.Serving.batched_run(name, padded)) == [21.0, 23.0]

    {{values}, {masks}, quality} =
      Nx.Defn.jit_apply(&Function.identity/1, [batch], compiler: Nx.Defn.Evaluator)

    one_row = fn index ->
      Nx.Batch.stack([
        {{values[index..index]}, {masks[index..index]}, quality[index..index]}
      ])
    end

    tasks =
      for index <- 0..1 do
        Task.async(fn ->
          {index, Nx.to_flat_list(Nx.Serving.batched_run(name, one_row.(index)))}
        end)
      end

    assert Enum.sort(Enum.map(tasks, &Task.await/1)) == [{0, [21.0]}, {1, [23.0]}]

    timeout_flush = Task.async(fn -> Nx.Serving.batched_run(name, one_row.(0)) end)
    assert {:ok, result} = Task.yield(timeout_flush, 1_000)
    assert Nx.to_flat_list(result) == [21.0]

    keyed = Nx.Batch.key(batch, :room_a)
    assert Nx.to_flat_list(Nx.Serving.batched_run(name, keyed)) == [21.0, 23.0]

    assert {:error, :max_children} =
             Lab.start_child(
               lab,
               :sessions,
               {Nx.Serving, serving: serving, name: :wotex_lab_serving_over_capacity, batch_size: 1}
             )

    assert :ok = Lab.stop_child(lab, :sessions, serving_pid)
    refute Process.alive?(serving_pid)
    assert Process.whereis(name) == nil
    assert :ok = Supervisor.stop(lab)
  end

  test "stopping an instance child terminates an executing Serving worker and caller" do
    {:ok, lab} = Lab.start_link(id: "serving-stop-test", max_children: 1)
    name = :wotex_lab_blocking_serving_test
    serving = Nx.Serving.new(BlockingServing, self())

    child =
      {Nx.Serving, serving: serving, name: name, batch_size: 1, batch_timeout: 1}
      |> Supervisor.child_spec(shutdown: 50)

    {:ok, serving_pid} = Lab.start_child(lab, :sessions, child)
    parent = self()
    batch = Nx.Batch.stack([Nx.tensor(1.0)])

    {caller, caller_monitor} =
      spawn_monitor(fn ->
        outcome =
          try do
            {:ok, Nx.Serving.batched_run(name, batch)}
          catch
            :exit, reason -> {:exit, reason}
          end

        send(parent, {:serving_caller, outcome})
      end)

    assert_receive {:serving_execution, worker}
    worker_monitor = Process.monitor(worker)
    assert :ok = Lab.stop_child(lab, :sessions, serving_pid)
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _}
    assert_receive {:serving_caller, {:exit, _}}
    assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :normal}
    assert Process.whereis(name) == nil
    assert :ok = Supervisor.stop(lab)
  end
end
