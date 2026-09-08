defmodule WotexLabWorkbench.Investigation.Deadline do
  @moduledoc "Runs disposable provider work and kills it on timeout or caller death."

  @doc "Returns the result, an exit reason or a timeout; no worker survives the boundary."
  @spec run((-> term()), non_neg_integer()) :: {:ok, term()} | {:error, term()}
  def run(fun, timeout) when is_function(fun, 0) and is_integer(timeout) and timeout >= 0 do
    owner = self()
    token = make_ref()
    callers = [owner | Process.get(:"$callers", [])]
    {pid, monitor} = spawn_monitor(fn -> supervise(owner, token, callers, fun, timeout) end)

    receive do
      {^token, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        {:error, reason}
    end
  end

  defp supervise(owner, token, callers, fun, timeout) do
    Process.flag(:trap_exit, true)
    Process.put(:"$callers", callers)
    owner_monitor = Process.monitor(owner)
    task = Task.async(fun)
    task_ref = task.ref

    result =
      receive do
        {^task_ref, value} -> {:ok, value}
        {:DOWN, ^task_ref, :process, _, reason} -> {:error, reason}
        {:DOWN, ^owner_monitor, :process, _, _} -> {:error, :caller_down}
      after
        timeout -> {:error, :timeout}
      end

    Task.shutdown(task, :brutal_kill)
    send(owner, {token, result})
  end
end
