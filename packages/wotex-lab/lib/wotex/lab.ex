defmodule Wotex.Lab do
  @moduledoc """
  Explicit OTP composition for an independent WoT and Nx consumer laboratory.

  Loading this library starts no Lab instance. Add `child_spec/1` to your own
  supervisor or call `start_link/1`. Each instance owns separate bounded Thing
  and session supervisors. The numerical example can also run without an instance.

  Instances are consumer composition roots rather than framework-wide
  registries. Their identifiers and capacities are supplied explicitly, and
  independent trees can coexist without shared process names or application
  configuration. Dependency applications retain their own documented startup
  behavior.

  `start_child/3` and `stop_child/3` address the two instance roles through a
  live supervisor PID. They accept trusted in-process child specifications;
  scenario data and network input must never select modules or executable child
  terms. Restart, shutdown, and resource ownership otherwise follow the child
  specification and ordinary OTP supervision semantics.
  """

  @doc "Returns an ordinary supervisor child specification with a caller-supplied ID."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  defdelegate child_spec(opts), to: Wotex.Lab.Supervisor

  @doc "Starts a Lab supervisor; requires `:id`, with optional `:name` and `:max_children`."
  @spec start_link(keyword()) :: Supervisor.on_start() | {:error, Wotex.Lab.Error.t()}
  defdelegate start_link(opts), to: Wotex.Lab.Supervisor

  @doc "Starts a trusted child specification under a live instance's Thing or session supervisor."
  @spec start_child(pid(), :things | :sessions, Supervisor.child_spec() | {module(), term()}) ::
          DynamicSupervisor.on_start_child() | {:error, Wotex.Lab.Error.t()}
  defdelegate start_child(instance, role, child), to: Wotex.Lab.Supervisor

  @doc "Terminates a child started under a live instance's Thing or session supervisor."
  @spec stop_child(pid(), :things | :sessions, pid()) ::
          :ok | {:error, Wotex.Lab.Error.t() | :not_found}
  defdelegate stop_child(instance, role, child), to: Wotex.Lab.Supervisor
end
