defmodule Wotex.Lab.SupervisorTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab
  alias Wotex.Lab.Error

  test "simultaneous instances isolate state and capacity for both roles" do
    first = start_supervised!({Lab, id: "first", max_children: 1})
    second = start_supervised!({Lab, id: "second", max_children: 1})

    for role <- [:things, :sessions] do
      assert {:ok, a} = Lab.start_child(first, role, {Agent, fn -> :first end})
      assert {:ok, b} = Lab.start_child(second, role, {Agent, fn -> :second end})
      assert Agent.get(a, & &1) == :first
      assert Agent.get(b, & &1) == :second
      assert {:error, :max_children} = Lab.start_child(first, role, {Agent, fn -> :overflow end})
    end
  end

  test "root shutdown releases owned children and leaves another instance alive" do
    first = start_supervised!({Lab, id: "first"})
    second = start_supervised!({Lab, id: "second"})
    assert {:ok, owned} = Lab.start_child(first, :things, {Agent, fn -> :state end})
    assert {:ok, independent} = Lab.start_child(second, :sessions, {Agent, fn -> :state end})
    monitor = Process.monitor(owned)

    assert :ok = stop_supervised({Lab.Supervisor, "first"})
    assert_receive {:DOWN, ^monitor, :process, ^owned, :shutdown}
    assert Process.alive?(independent)
  end

  test "a stopped role is unavailable while the sibling role continues" do
    lab = start_supervised!({Lab, id: "roles"})
    assert {:ok, session} = Lab.start_child(lab, :sessions, {Agent, fn -> :connected end})
    assert :ok = Supervisor.terminate_child(lab, :things)

    assert {:error, %Error{code: :supervisor_unavailable}} =
             Lab.start_child(lab, :things, {Agent, fn -> :state end})

    assert Process.alive?(session)
    assert {:ok, _role} = Supervisor.restart_child(lab, :things)
    assert {:ok, _child} = Lab.start_child(lab, :things, {Agent, fn -> :new_state end})
  end

  test "killing one role restarts only that role while the sibling keeps its children" do
    lab = start_supervised!({Lab, id: "kill-isolation"})
    assert {:ok, session} = Lab.start_child(lab, :sessions, {Agent, fn -> :connected end})

    {:things, things, :supervisor, _modules} =
      List.keyfind(Supervisor.which_children(lab), :things, 0)

    {:sessions, sessions, :supervisor, _modules} =
      List.keyfind(Supervisor.which_children(lab), :sessions, 0)

    monitor = Process.monitor(things)

    Process.exit(things, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^things, :killed}
    assert Process.alive?(sessions)
    assert Process.alive?(session)
    assert Agent.get(session, & &1) == :connected

    assert {:ok, _child} = wait_for_role(lab, :things)
  end

  test "child failure follows caller restart semantics" do
    lab = start_supervised!({Lab, id: "restart"})
    receiver = self()

    assert {:ok, child} =
             Lab.start_child(
               lab,
               :things,
               {Agent,
                fn ->
                  send(receiver, {:started, self()})
                  :original
                end}
             )

    assert_receive {:started, ^child}
    monitor = Process.monitor(child)
    Agent.update(child, fn _state -> :changed end)
    Process.exit(child, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^child, :killed}
    assert_receive {:started, replacement}
    assert replacement != child
    assert Agent.get(replacement, & &1) == :original
  end

  defp wait_for_role(lab, role, attempts \\ 50) do
    case Lab.start_child(lab, role, {Agent, fn -> :restarted end}) do
      {:ok, child} ->
        {:ok, child}

      {:error, %Error{code: :supervisor_unavailable}} when attempts > 0 ->
        Process.sleep(10)
        wait_for_role(lab, role, attempts - 1)

      other ->
        other
    end
  end

  test "named startup and child identity use explicit caller inputs" do
    name = {:global, {:lab_test, make_ref()}}
    assert {:ok, lab} = Lab.start_link(id: "named", name: name)
    assert :global.whereis_name(elem(name, 1)) == lab
    assert Lab.child_spec(id: "named").id == {Lab.Supervisor, "named"}
    Supervisor.stop(lab)

    atom_name = :"lab_test_#{System.unique_integer([:positive])}"
    assert {:ok, atom_lab} = Lab.start_link(id: "atom-named", name: atom_name)
    assert Process.whereis(atom_name) == atom_lab
    Supervisor.stop(atom_lab)
  end

  test "duplicate IDs cannot be silently attached to one parent" do
    first = start_supervised!({Lab, id: "duplicate"})
    assert {:error, {:already_started, ^first}} = start_supervised({Lab, id: "duplicate"})
  end

  test "caller-owned Registry registration scopes names without creating Lab globals" do
    registry = Module.concat(__MODULE__, Registry)
    start_supervised!({Registry, keys: :unique, name: registry})
    name = {:via, Registry, {registry, "room"}}
    lab = start_supervised!({Lab, id: "registered", name: name})
    assert Registry.lookup(registry, "room") == [{lab, nil}]
    assert :ok = stop_supervised({Lab.Supervisor, "registered"})
    refute Process.alive?(lab)
    replacement = start_supervised!({Lab, id: "registered", name: name})
    assert Registry.lookup(registry, "room") == [{replacement, nil}]
  end

  test "invalid options are rejected before any child starts" do
    for opts <- [nil, %{}, [:bad], [id: "a", id: "b"], [id: "a", secret: "sentinel"]] do
      assert {:error, %Error{code: :invalid_options}} = Lab.start_link(opts)
      assert_raise ArgumentError, fn -> Lab.child_spec(opts) end
    end

    for opts <- [
          [],
          [id: ""],
          [id: :atom],
          [id: "a", name: "string"],
          [id: "a", max_children: 0],
          [id: "a", max_children: 10_001],
          [id: "a", max_children: 1.5]
        ] do
      assert {:error, %Error{code: :invalid_instance}} = Lab.start_link(opts)
      assert_raise ArgumentError, fn -> Lab.child_spec(opts) end
    end

    assert {:error, %Error{code: :unknown_role}} = Lab.start_child(self(), :unknown, %{})
  end
end
