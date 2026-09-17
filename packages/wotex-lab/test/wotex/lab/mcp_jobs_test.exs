defmodule Wotex.Lab.MCPJobsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error
  alias Wotex.Lab.MCP.{Jobs, Server}

  @session "session-key-0123456789abcdef"

  defp slow(ms), do: %{run: fn -> Process.sleep(ms) end, dimensions: %{queue: 1}}

  defp jobs(opts \\ []) do
    workloads = %{"slow" => slow(20), "fast" => %{run: fn -> :ok end, dimensions: %{queue: 1}}}
    start_supervised!({Jobs, Keyword.merge([workloads: workloads], opts)})
  end

  defp await(jobs, session, job, status, attempts \\ 200) do
    case Jobs.status(jobs, session, job) do
      {:ok, %{"status" => ^status} = reply} ->
        reply

      {:ok, _} when attempts > 0 ->
        Process.sleep(10)
        await(jobs, session, job, status, attempts - 1)

      other ->
        flunk("job did not reach #{status}: #{inspect(other)}")
    end
  end

  test "the default catalogue measures packaged fixtures as informational records" do
    owner = start_supervised!(Jobs)
    assert Jobs.workloads(owner) == ["json-decode", "td-canonical-encode", "td-parse"]

    for workload <- Jobs.workloads(owner) do
      assert {:ok, %{"job_id" => job, "status" => "running"}} =
               Jobs.start(owner, @session, workload, 5)

      reply = await(owner, @session, job, "completed")
      assert reply["workload"] == workload and reply["samples"] == 5
      assert reply["result"]["kind"] == "wotex_lab_benchmark"
      assert reply["result"]["correctness"] == "not_evaluated"
      assert reply["result"]["mode"] == "informational"
    end
  end

  test "running, admitted and retained jobs are bounded per session" do
    owner = jobs(max_jobs: 6, max_retained: 2)
    assert {:ok, %{"job_id" => first}} = Jobs.start(owner, @session, "slow", 10)
    assert {:error, %Error{code: :job_busy}} = Jobs.start(owner, @session, "fast", 1)

    other = "other-session-key-0123456789"
    assert {:ok, %{"job_id" => foreign}} = Jobs.start(owner, other, "fast", 1)
    assert {:error, %Error{code: :unknown_job}} = Jobs.status(owner, @session, foreign)

    await(owner, @session, first, "completed")

    finished =
      for _ <- 1..5 do
        {:ok, %{"job_id" => job}} = Jobs.start(owner, @session, "fast", 1)
        await(owner, @session, job, "completed")
        job
      end

    assert {:error, %Error{code: :job_quota_exhausted}} = Jobs.start(owner, @session, "fast", 1)
    assert {:error, %Error{code: :unknown_job}} = Jobs.status(owner, @session, first)
    assert Enum.count(finished, &match?({:ok, _}, Jobs.status(owner, @session, &1))) == 2
  end

  test "cancellation, deadlines, crashes and closing kill the owned worker" do
    workloads = %{
      "slow" => slow(50),
      "crash" => %{run: fn -> Process.exit(self(), :kill) end, dimensions: %{queue: 1}},
      "raise" => %{run: fn -> raise "secret-sentinel" end, dimensions: %{queue: 1}}
    }

    owner = start_supervised!({Jobs, workloads: workloads, deadline_ms: 300, max_jobs: 16})

    assert {:ok, %{"job_id" => job}} = Jobs.start(owner, @session, "slow", 200)
    worker = running_worker(owner)
    ref = Process.monitor(worker)
    assert {:ok, %{"status" => "cancelled"}} = Jobs.cancel(owner, @session, job)
    assert_receive {:DOWN, ^ref, :process, ^worker, :killed}
    assert {:ok, %{"status" => "cancelled"}} = Jobs.cancel(owner, @session, job)

    assert {:ok, %{"job_id" => late}} = Jobs.start(owner, @session, "slow", 200)
    assert %{"status" => "timed_out"} = await(owner, @session, late, "timed_out")

    assert {:ok, %{"job_id" => crashed}} = Jobs.start(owner, @session, "crash", 1)
    assert %{"error" => "job_crashed"} = await(owner, @session, crashed, "failed")

    assert {:ok, %{"job_id" => raised}} = Jobs.start(owner, @session, "raise", 1)
    reply = await(owner, @session, raised, "failed")
    refute inspect(reply) =~ "secret-sentinel"

    assert {:ok, %{"job_id" => closed}} = Jobs.start(owner, @session, "slow", 200)
    worker = running_worker(owner)
    ref = Process.monitor(worker)
    assert :ok = Jobs.close(owner, @session)
    assert_receive {:DOWN, ^ref, :process, ^worker, :killed}
    assert {:error, %Error{code: :unknown_job}} = Jobs.status(owner, @session, closed)
    assert :sys.get_state(owner).workers == %{}
  end

  test "idle sessions expire and malformed input starts no work" do
    owner = jobs(idle_ms: 50)
    assert {:ok, %{"job_id" => job}} = Jobs.start(owner, @session, "fast", 1)
    await(owner, @session, job, "completed")
    Process.sleep(120)
    assert {:error, %Error{code: :unknown_job}} = Jobs.status(owner, @session, job)

    for {session, workload, samples, code} <- [
          {"short", "fast", 1, :invalid_session},
          {@session, "System.cmd", 1, :unknown_workload},
          {@session, :fast, 1, :unknown_workload},
          {@session, "fast", 0, :invalid_samples},
          {@session, "fast", 201, :invalid_samples},
          {@session, "fast", "1", :invalid_samples}
        ] do
      assert {:error, %Error{code: ^code}} = Jobs.start(owner, session, workload, samples)
    end

    assert :sys.get_state(owner).workers == %{}

    for opts <- [
          [max_running: 0],
          [deadline_ms: 60_001],
          [workloads: %{"BAD ID" => slow(1)}],
          [workloads: %{"ok" => %{run: :not_a_function, dimensions: %{}}}],
          [unknown: 1]
        ] do
      assert {:error, %Error{code: :invalid_jobs}} = Jobs.start_link(opts)
    end

    dead = spawn(fn -> :ok end)
    Process.sleep(10)
    assert {:error, %Error{code: :jobs_unavailable}} = Jobs.status(dead, @session, "job")
  end

  test "MCP sessions list, start, poll and cancel jobs only when a job owner is bound" do
    unbound = session([])
    refute "start_benchmark" in tool_names(unbound)

    assert {%{"error" => %{"code" => -32_601}}, _} =
             call(unbound, "start_benchmark", %{"workload" => "fast"})

    owner = jobs()
    first = session(jobs: owner)
    second = session(jobs: owner)
    assert first.session_key != second.session_key

    assert {"benchmark_status" in tool_names(first), "cancel_benchmark" in tool_names(first)} ==
             {true, true}

    assert {%{"result" => %{"isError" => false, "structuredContent" => started}}, first} =
             call(first, "start_benchmark", %{"workload" => "slow", "samples" => 3})

    job = started["job_id"]

    assert {%{"result" => %{"isError" => true, "structuredContent" => %{"error" => "unknown_job"}}},
            _} = call(second, "benchmark_status", %{"job_id" => job})

    assert {%{"error" => %{"code" => -32_602}}, _} =
             call(first, "start_benchmark", %{"workload" => "fast", "module" => "System"})

    await(owner, first.session_key, job, "completed")

    assert {%{"result" => %{"structuredContent" => %{"status" => "completed", "result" => record}}},
            _} = call(first, "benchmark_status", %{"job_id" => job})

    assert record["samples"] == 3
    assert {:error, %Error{code: :invalid_options}} = Server.new(jobs: :owner)
  end

  defp running_worker(owner) do
    [worker] = owner |> :sys.get_state() |> Map.fetch!(:workers) |> Map.keys()
    worker
  end

  defp session(opts) do
    {:ok, state} = Server.new(opts)

    {_, state} =
      Server.handle(state, request(1, "initialize", %{"protocolVersion" => "2025-11-25"}))

    {nil, state} =
      Server.handle(state, %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

    state
  end

  defp tool_names(state) do
    {reply, _} = Server.handle(state, request(2, "tools/list", %{}))
    Enum.map(reply["result"]["tools"], & &1["name"])
  end

  defp call(state, name, arguments),
    do: Server.handle(state, request(3, "tools/call", %{"name" => name, "arguments" => arguments}))

  defp request(id, method, params),
    do: %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}
end
