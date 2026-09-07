defmodule Wotex.Lab do
  @moduledoc """
  Explicit OTP composition for an independent WoT and Nx consumer laboratory.

  Loading this library starts no Lab instance. Add `child_spec/1` to your own
  supervisor or call `start_link/1`. Each instance owns separate bounded Thing
  and session supervisors. The numerical example can also run without an instance.
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
end
