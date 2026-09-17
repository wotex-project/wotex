defmodule Wotex.Lab.MCP.Jobs do
  @moduledoc """
  Host-owned, bounded benchmark jobs for MCP sessions.

  A host explicitly starts this process and passes it to
  `Wotex.Lab.MCP.Server.new/1` as `:jobs`. Each session receives a random key, so
  a job identifier is useful only inside the session that started it. The
  process owns every worker: a job survives the transport process that
  admitted it, which lets a Streamable HTTP session poll from later requests.

  Workloads come from a closed catalogue of zero-arity operations over packaged
  fixtures, measured with `Wotex.Lab.Benchmark`. A trusted host may replace the
  catalogue through `:workloads`; tool arguments select an identifier and a
  sample count, never code. Limits bound the work: one running job per session,
  at most eight admitted jobs per session, four retained terminal results, a
  10-second job deadline, 200 samples and 65,536 result bytes by default.
  Cancelling a running job kills its worker; a finished job keeps its terminal
  status. A session idle for 15 minutes, or closed explicitly, loses its jobs.
  Results are informational benchmark records, never correctness evidence.
  """

  use GenServer

  alias Wotex.Lab.{Benchmark, Error, Options}
  alias Wotex.ThingDescription

  @options ~w(workloads max_running max_jobs max_retained deadline_ms max_samples max_result_bytes idle_ms)a
  @defaults %{
    max_running: 1,
    max_jobs: 8,
    max_retained: 4,
    deadline_ms: 10_000,
    max_samples: 200,
    max_result_bytes: 65_536,
    idle_ms: 900_000
  }
  @ceilings %{
    max_running: 4,
    max_jobs: 128,
    max_retained: 32,
    deadline_ms: 60_000,
    max_samples: 10_000,
    max_result_bytes: 1_048_576,
    idle_ms: 3_600_000
  }

  @typedoc "A job status map returned to a session."
  @type status :: %{String.t() => term()}

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: {__MODULE__, make_ref()}, start: {__MODULE__, :start_link, [opts]}, restart: :temporary}
  end

  @doc "Starts a job owner; invalid options start no process."
  @spec start_link(keyword()) :: GenServer.on_start() | {:error, Error.t()}
  def start_link(opts \\ []) do
    with {:ok, config} <- configure(opts), do: GenServer.start_link(__MODULE__, config)
  end

  @doc "The identifiers of the admitted workloads."
  @spec workloads(pid()) :: [String.t()] | {:error, Error.t()}
  def workloads(jobs), do: call(jobs, :workloads)

  @doc "Admits one job for `session` and returns its identifier and running status."
  @spec start(pid(), String.t(), term(), term()) :: {:ok, status()} | {:error, Error.t()}
  def start(jobs, session, workload, samples), do: call(jobs, {:start, session, workload, samples})

  @doc "Returns the current status of one job of `session`."
  @spec status(pid(), String.t(), term()) :: {:ok, status()} | {:error, Error.t()}
  def status(jobs, session, job), do: call(jobs, {:status, session, job})

  @doc "Cancels a running job; a terminal job keeps its status."
  @spec cancel(pid(), String.t(), term()) :: {:ok, status()} | {:error, Error.t()}
  def cancel(jobs, session, job), do: call(jobs, {:cancel, session, job})

  @doc "Kills the running work of `session` and forgets its jobs."
  @spec close(pid(), String.t()) :: :ok | {:error, Error.t()}
  def close(jobs, session), do: call(jobs, {:close, session})

  @doc "A random session key for `Wotex.Lab.MCP.Server`."
  @spec session_key() :: String.t()
  def session_key, do: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

  @impl GenServer
  def init(config) do
    Process.flag(:trap_exit, true)
    {:ok, Map.merge(config, %{sessions: %{}, workers: %{}})}
  end

  @impl GenServer
  def handle_call(:workloads, _, state),
    do: {:reply, state.workloads |> Map.keys() |> Enum.sort(), state}

  def handle_call({:start, session, workload, samples}, _, state) do
    with :ok <- session_key(session),
         {:ok, operation} <- workload(state, workload),
         {:ok, samples} <- samples(state, samples),
         entry = entry(state, session),
         :ok <- running_capacity(state, entry),
         :ok <- job_capacity(state, entry) do
      {job, state} = launch(state, session, entry, workload, operation, samples)
      {:reply, {:ok, public(job, state, session)}, state}
    else
      {:error, _} = error -> {:reply, error, touch(state, session)}
    end
  end

  def handle_call({:status, session, job}, _, state) do
    with :ok <- session_key(session), {:ok, record} <- find(state, session, job) do
      {:reply, {:ok, public(job, record)}, touch(state, session)}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:cancel, session, job}, _, state) do
    with :ok <- session_key(session), {:ok, record} <- find(state, session, job) do
      state =
        if record.status == "running",
          do: finish(state, session, job, "cancelled", %{}),
          else: state

      {:reply, {:ok, public(job, state, session)}, touch(state, session)}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:close, session}, _, state) do
    with :ok <- session_key(session) do
      {:reply, :ok, drop_session(state, session)}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_info({:job_result, worker, result}, state) do
    case Map.get(state.workers, worker) do
      {session, job, _, _} ->
        {status, fields} = outcome(state, result)
        {:noreply, finish(state, session, job, status, fields)}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, _, :process, worker, _}, state) do
    case Map.get(state.workers, worker) do
      {session, job, _, _} ->
        {:noreply, finish(state, session, job, "failed", %{"error" => "job_crashed"})}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info({:job_deadline, worker}, state) do
    case Map.get(state.workers, worker) do
      {session, job, _, _} -> {:noreply, finish(state, session, job, "timed_out", %{})}
      nil -> {:noreply, state}
    end
  end

  def handle_info({:idle, session, stamp}, state) do
    case state.sessions do
      %{^session => %{stamp: ^stamp}} -> {:noreply, drop_session(state, session)}
      _ -> {:noreply, state}
    end
  end

  def handle_info({:EXIT, _, _}, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) do
    Enum.each(Map.keys(state.workers), &Process.exit(&1, :kill))
  end

  defp launch(state, session, entry, workload, operation, samples) do
    owner = self()
    job = "job-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)

    {worker, monitor} =
      spawn_monitor(fn ->
        result =
          try do
            Benchmark.run(workload, operation.run, benchmark_options(operation, samples))
          rescue
            _ -> {:error, Error.new(:job_failed, :running, "benchmark workload raised")}
          catch
            _, _ -> {:error, Error.new(:job_failed, :running, "benchmark workload failed")}
          end

        send(owner, {:job_result, self(), result})
      end)

    timer = Process.send_after(self(), {:job_deadline, worker}, state.deadline_ms)
    record = %{status: "running", workload: workload, samples: samples, fields: %{}, worker: worker}

    entry = %{
      entry
      | jobs: Map.put(entry.jobs, job, record),
        order: entry.order ++ [job],
        admitted: entry.admitted + 1
    }

    state = %{
      state
      | sessions: Map.put(state.sessions, session, entry),
        workers: Map.put(state.workers, worker, {session, job, monitor, timer})
    }

    {job, touch(state, session)}
  end

  defp finish(state, session, job, status, fields) do
    with %{jobs: %{^job => %{status: "running", worker: worker} = record}} = entry <-
           Map.get(state.sessions, session) do
      {_, _, monitor, timer} = Map.fetch!(state.workers, worker)
      Process.demonitor(monitor, [:flush])
      Process.cancel_timer(timer)
      Process.exit(worker, :kill)
      flush_result(worker)
      record = %{record | status: status, fields: fields, worker: nil}
      entry = retain(%{entry | jobs: Map.put(entry.jobs, job, record)}, state.max_retained)

      %{
        state
        | sessions: Map.put(state.sessions, session, entry),
          workers: Map.delete(state.workers, worker)
      }
    else
      _ -> state
    end
  end

  defp retain(entry, limit) do
    terminal = Enum.filter(entry.order, &(entry.jobs[&1].status != "running"))
    evicted = Enum.take(terminal, max(length(terminal) - limit, 0))

    %{
      entry
      | jobs: Map.drop(entry.jobs, evicted),
        order: entry.order -- evicted
    }
  end

  defp drop_session(state, session) do
    case Map.pop(state.sessions, session) do
      {nil, _} ->
        state

      {entry, sessions} ->
        workers =
          Enum.reduce(entry.jobs, state.workers, fn
            {_, %{worker: worker}}, workers when is_pid(worker) ->
              {_, _, monitor, timer} = Map.fetch!(workers, worker)
              Process.demonitor(monitor, [:flush])
              Process.cancel_timer(timer)
              Process.exit(worker, :kill)
              flush_result(worker)
              Map.delete(workers, worker)

            _, workers ->
              workers
          end)

        %{state | sessions: sessions, workers: workers}
    end
  end

  defp flush_result(worker) do
    receive do
      {:job_result, ^worker, _} -> :ok
    after
      0 -> :ok
    end
  end

  defp outcome(state, {:ok, record}) do
    if byte_size(:erlang.term_to_binary(record)) <= state.max_result_bytes,
      do: {"completed", %{"result" => record}},
      else: {"failed", %{"error" => "result_too_large"}}
  end

  defp outcome(_, {:error, %Error{code: code}}), do: {"failed", %{"error" => Atom.to_string(code)}}
  defp outcome(_, _), do: {"failed", %{"error" => "job_failed"}}

  defp entry(state, session),
    do: Map.get(state.sessions, session, %{jobs: %{}, order: [], admitted: 0, stamp: nil})

  defp touch(state, session) do
    case Map.fetch(state.sessions, session) do
      {:ok, entry} ->
        stamp = make_ref()
        Process.send_after(self(), {:idle, session, stamp}, state.idle_ms)
        %{state | sessions: Map.put(state.sessions, session, %{entry | stamp: stamp})}

      :error ->
        state
    end
  end

  defp running_capacity(state, entry) do
    running = Enum.count(entry.jobs, fn {_, record} -> record.status == "running" end)

    if running < state.max_running,
      do: :ok,
      else: failure(:job_busy, "the session already runs its admitted number of jobs")
  end

  defp job_capacity(state, entry) do
    if entry.admitted < state.max_jobs,
      do: :ok,
      else: failure(:job_quota_exhausted, "the session job quota is exhausted")
  end

  defp find(state, session, job) when is_binary(job) and byte_size(job) <= 64 do
    case state.sessions do
      %{^session => %{jobs: %{^job => record}}} -> {:ok, record}
      _ -> failure(:unknown_job, "job is not retained for this session")
    end
  end

  defp find(_, _, _), do: failure(:unknown_job, "job is not retained for this session")

  defp public(job, state, session), do: public(job, state.sessions[session].jobs[job])

  defp public(job, record) do
    Map.merge(record.fields, %{
      "job_id" => job,
      "status" => record.status,
      "workload" => record.workload,
      "samples" => record.samples
    })
  end

  defp workload(state, workload) when is_binary(workload) do
    case Map.fetch(state.workloads, workload) do
      {:ok, operation} -> {:ok, operation}
      :error -> failure(:unknown_workload, "workload is not admitted")
    end
  end

  defp workload(_, _), do: failure(:unknown_workload, "workload is not admitted")

  defp samples(state, samples) when is_integer(samples) and samples >= 1,
    do:
      if(samples <= state.max_samples,
        do: {:ok, samples},
        else: failure(:invalid_samples, "sample count exceeds the job limit")
      )

  defp samples(_, _), do: failure(:invalid_samples, "sample count must be a positive integer")

  defp session_key(session) when is_binary(session) and byte_size(session) in 16..64, do: :ok
  defp session_key(_), do: failure(:invalid_session, "session key is not admitted")

  defp benchmark_options(operation, samples) do
    [
      dimensions: operation.dimensions,
      runner: "mcp-jobs",
      backend: "beam",
      cohort: "mcp-session",
      baseline: "none",
      machine: "host-local",
      samples: samples,
      warmup: 1,
      shared: true
    ]
  end

  defp configure(opts) do
    with :ok <- Options.validate(opts, @options),
         limits = Map.merge(@defaults, Map.new(Keyword.delete(opts, :workloads))),
         true <- Enum.all?(@ceilings, fn {key, max} -> bounded?(limits[key], max) end),
         {:ok, workloads} <- workloads_option(Keyword.get(opts, :workloads, :default)) do
      {:ok, Map.put(limits, :workloads, workloads)}
    else
      _ -> failure(:invalid_jobs, "job options are not admitted")
    end
  end

  defp bounded?(value, max), do: is_integer(value) and value >= 1 and value <= max

  defp workloads_option(:default), do: {:ok, default_workloads()}

  defp workloads_option(workloads) when is_map(workloads) and map_size(workloads) in 1..32 do
    if Enum.all?(workloads, fn {id, operation} ->
         is_binary(id) and Regex.match?(~r/\A[a-z0-9][a-z0-9._-]{0,63}\z/, id) and
           match?(
             %{run: run, dimensions: dimensions} when is_function(run, 0) and is_map(dimensions),
             operation
           )
       end),
       do: {:ok, workloads},
       else: :error
  end

  defp workloads_option(_), do: :error

  defp default_workloads do
    path = Application.app_dir(:wotex_lab, "priv/fixtures/loopback/thing-description.json")
    bytes = File.read!(path)
    {:ok, td} = ThingDescription.parse(bytes)

    %{
      "json-decode" => %{
        run: fn -> Wotex.JSON.decode(bytes) end,
        dimensions: %{bytes: byte_size(bytes)}
      },
      "td-parse" => %{
        run: fn -> ThingDescription.parse(bytes) end,
        dimensions: %{bytes: byte_size(bytes)}
      },
      "td-canonical-encode" => %{
        run: fn -> ThingDescription.encode(td, :canonical) end,
        dimensions: %{bytes: byte_size(bytes)}
      }
    }
  end

  defp call(jobs, message) when is_pid(jobs) and node(jobs) == node() do
    GenServer.call(jobs, message, 5_000)
  catch
    :exit, _ -> failure(:jobs_unavailable, "the job owner is unavailable")
  end

  defp call(_, _), do: failure(:jobs_unavailable, "the job owner is unavailable")

  defp failure(code, message), do: {:error, Error.new(code, :admission, message)}
end
