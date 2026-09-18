defmodule Wotex.Lab.Test.CookbookRunner do
  @moduledoc false

  # Evaluates a cookbook's Elixir cells in order, the way Livebook's evaluator
  # does: one binding and one `Macro.Env` threaded through every cell, so
  # aliases and variables defined in one cell are visible in the next. The
  # `Mix.install/1` cell is skipped explicitly; artifact installation belongs
  # to Livebook, never to the test suite.
  #
  # Each evaluation owns a run: an unlinked evaluator process, a dedicated
  # group leader that forwards IO to the caller's group leader, and one trace
  # session whose tracer is that group leader. The session follows every
  # process the evaluator spawns, transitively, and records the handler
  # identifier of each `:telemetry.attach/4` or `:telemetry.attach_many/4`
  # call those processes make. When the last cell has run, every process still
  # linked to the evaluator is signalled and counted as `leaked`. However the
  # run ends (last cell, raised cell, evaluator exit or timeout), the runner
  # then kills the evaluator and every run process still alive, meaning a
  # traced descendant or a holder of the run group leader, and detaches every
  # recorded handler that is still attached. `reclaimed` counts both.
  #
  # Bindings grant no cleanup authority: a caller pid or directory passed in a
  # binding is not a run process and is never signalled or deleted. The runner
  # is not a sandbox. Cells run in this VM with full authority, so a process
  # started by a process outside the run without the run group leader is not
  # reclaimed, and isolation of arbitrary notebook code is not claimed. It
  # accepts catalogue identifiers and the checked-in lifecycle fixtures under
  # `test/fixtures/cookbooks/`, never submitted code.

  alias Wotex.Lab.Cookbook

  @fixtures Path.expand("../fixtures/cookbooks", __DIR__)
  @fixture_name ~r/\A[a-z][a-z-]{0,62}\z/
  @session :wotex_lab_cookbook_run
  @attach [attach: 4, attach_many: 4]
  @passes 8
  @kill_wait_ms 5_000

  @type reclaimed :: %{processes: non_neg_integer(), handlers: non_neg_integer()}

  @type outcome :: %{
          result: term(),
          binding: keyword(),
          cells: non_neg_integer(),
          modules: [module()],
          leaked: non_neg_integer(),
          reclaimed: reclaimed()
        }

  @spec run(String.t(), keyword()) :: {:ok, outcome()} | {:error, map()}
  def run(id, opts \\ []) do
    with {:ok, entry} <- Cookbook.fetch(id),
         {:ok, source} <- Cookbook.read(id) do
      evaluate(entry.path, source, Keyword.get(opts, :timeout, entry.timeout_ms), opts)
    end
  end

  @spec run_fixture(String.t(), keyword()) :: {:ok, outcome()} | {:error, map()}
  def run_fixture(name, opts) when is_binary(name) do
    true = Regex.match?(@fixture_name, name)
    path = Path.join(@fixtures, name <> ".livemd")
    evaluate(path, File.read!(path), Keyword.fetch!(opts, :timeout), opts)
  end

  @spec install_cell?(binary()) :: boolean()
  def install_cell?(cell), do: String.starts_with?(String.trim_leading(cell), "Mix.install(")

  defp evaluate(file, source, timeout, opts) do
    cells =
      source
      |> Cookbook.cells()
      |> Enum.reject(&install_cell?/1)

    seed = Keyword.get(opts, :binding, [])
    caller = self()
    ref = make_ref()
    owner = spawn(fn -> owner(Process.group_leader(), MapSet.new(), MapSet.new()) end)

    evaluator =
      spawn(fn ->
        receive do
          {:go, ^ref} -> send(caller, {ref, cells(file, cells, seed)})
        end
      end)

    monitor = Process.monitor(evaluator)
    Process.group_leader(evaluator, owner)
    session = :trace.session_create(@session, owner, [])
    Enum.each(@attach, fn {name, arity} -> trace_function(session, name, arity) end)
    1 = :trace.process(session, evaluator, true, [:call, :procs, :set_on_spawn])
    send(evaluator, {:go, ref})

    {outcome, down} =
      receive do
        {^ref, outcome} ->
          {outcome, false}

        {:DOWN, ^monitor, :process, ^evaluator, reason} ->
          {{:error, %{cell: nil, kind: :exit, reason: reason}}, true}
      after
        timeout -> {{:error, %{cell: nil, kind: :timeout, reason: timeout}}, false}
      end

    if not down do
      Process.exit(evaluator, :kill)

      receive do
        {:DOWN, ^monitor, :process, ^evaluator, _} -> :ok
      end
    end

    reclaimed = reclaim(session, owner)
    :trace.session_destroy(session)
    Process.exit(owner, :kill)

    receive do
      {^ref, _} -> :ok
    after
      0 -> :ok
    end

    case outcome do
      {:ok, outcome} -> {:ok, Map.put(outcome, :reclaimed, reclaimed)}
      {:error, failure} -> {:error, Map.put(failure, :reclaimed, reclaimed)}
    end
  end

  defp trace_function(session, name, arity) do
    {:module, :telemetry} = Code.ensure_loaded(:telemetry)
    1 = :trace.function(session, {:telemetry, name, arity}, true, [:global])
  end

  defp cells(file, cells, seed) do
    env = Code.env_for_eval(file: file)

    outcome =
      cells
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, nil, seed, env}, fn {cell, index}, {:ok, _, binding, env} ->
        case eval_cell(cell, index, binding, env) do
          {:ok, value, binding, env} -> {:cont, {:ok, value, binding, env}}
          {:error, failure} -> {:halt, {:error, failure}}
        end
      end)

    case outcome do
      {:ok, value, binding, env} ->
        {:ok,
         %{
           result: value,
           binding: binding,
           cells: length(cells),
           modules: modules(cells, env),
           leaked: sweep_links()
         }}

      {:error, failure} ->
        _ = sweep_links()
        {:error, failure}
    end
  end

  defp eval_cell(cell, index, binding, env) do
    quoted = Code.string_to_quoted!(cell, file: env.file, line: 1)
    {value, binding, env} = Code.eval_quoted_with_env(quoted, binding, env)
    {:ok, value, binding, env}
  catch
    kind, reason ->
      {:error, %{cell: index, kind: kind, reason: reason, stacktrace: __STACKTRACE__}}
  end

  defp sweep_links do
    {:links, links} = Process.info(self(), :links)
    leaked = for pid <- links, is_pid(pid), do: pid
    Enum.each(leaked, &Process.exit(&1, :shutdown))
    length(leaked)
  end

  # The group leader of every run process and the tracer of the run session:
  # IO requests go to the caller's group leader, trace messages extend the
  # traced process set and the recorded handler identifiers.
  defp owner(group_leader, spawned, handlers) do
    receive do
      {:io_request, _, _, _} = request ->
        send(group_leader, request)
        owner(group_leader, spawned, handlers)

      {:trace, _, :spawn, child, _} ->
        owner(group_leader, MapSet.put(spawned, child), handlers)

      {:trace, _, :call, {:telemetry, _, [id | _]}} ->
        owner(group_leader, spawned, MapSet.put(handlers, id))

      {:run_state, from, ref} ->
        send(from, {ref, spawned, handlers})
        owner(group_leader, spawned, handlers)

      _ ->
        owner(group_leader, spawned, handlers)
    end
  end

  defp reclaim(session, owner) do
    processes = reclaim_processes(session, owner, MapSet.new(), @passes)
    {_, handlers} = run_state(session, owner)
    attached = MapSet.new(:telemetry.list_handlers([]), & &1.id)
    stale = MapSet.intersection(handlers, attached)
    Enum.each(stale, &:telemetry.detach/1)
    %{processes: MapSet.size(processes), handlers: MapSet.size(stale)}
  end

  defp reclaim_processes(_, _, killed, 0), do: killed

  defp reclaim_processes(session, owner, killed, passes) do
    {spawned, _} = run_state(session, owner)

    members =
      for pid <- Process.list(),
          pid != owner,
          MapSet.member?(spawned, pid) or
            Process.info(pid, :group_leader) == {:group_leader, owner},
          do: pid

    if members == [] do
      killed
    else
      monitors = Map.new(members, &{Process.monitor(&1), &1})
      Enum.each(members, &Process.exit(&1, :kill))
      await_down(monitors, System.monotonic_time(:millisecond) + @kill_wait_ms)
      reclaim_processes(session, owner, MapSet.union(killed, MapSet.new(members)), passes - 1)
    end
  end

  defp await_down(monitors, _) when map_size(monitors) == 0, do: :ok

  defp await_down(monitors, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:DOWN, monitor, :process, _, _} when is_map_key(monitors, monitor) ->
        await_down(Map.delete(monitors, monitor), deadline)
    after
      remaining -> raise "cookbook run processes survived an exit :kill"
    end
  end

  # Trace messages generated before this call are in the owner's mailbox
  # before the state request, so the snapshot includes them.
  defp run_state(session, owner) do
    delivered = :trace.delivered(session, :all)

    receive do
      {:trace_delivered, :all, ^delivered} -> :ok
    end

    ref = make_ref()
    send(owner, {:run_state, self(), ref})

    receive do
      {^ref, spawned, handlers} -> {spawned, handlers}
    end
  end

  defp modules(cells, env) do
    cells
    |> Enum.flat_map(fn cell ->
      cell
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        # `alias A.B.{C, D}`: the prefix is a namespace, not a module.
        {{:., _, [_, :{}]}, _, children}, acc ->
          {{:__block__, [], children}, acc}

        {:__aliases__, _, [first | _]} = node, acc when is_atom(first) ->
          {node, [Macro.expand(node, env) | acc]}

        node, acc ->
          {node, acc}
      end)
      |> elem(1)
    end)
    |> Enum.filter(&is_atom/1)
    |> Enum.uniq()
  end
end
