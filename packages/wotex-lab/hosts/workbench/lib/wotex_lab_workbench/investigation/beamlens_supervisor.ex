defmodule WotexLabWorkbench.Investigation.BeamlensSupervisor do
  @moduledoc """
  Bounded BeamLens 0.3.1 tree for one admitted operator.

  BeamLens does not propagate documented per-run iteration options to its
  static processes. This composition uses its public building blocks so the
  coordinator and operator both carry the real eight-turn limit. Reset replaces
  both processes, cancelling queued/current work and discarding conversation.
  The default skill is the trusted-local WoTEx skill. The hosted Escript may
  select the hosted skill inside its isolated, one-request VM.
  """

  use Supervisor

  alias WotexLabWorkbench.Investigation.Skill

  @max_iterations 8

  @doc false
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: Beamlens.Supervisor)
  end

  @doc "The hard model-turn ceiling stored in both BeamLens processes."
  @spec max_iterations() :: 8
  def max_iterations, do: @max_iterations

  @doc "Replaces the coordinator and operator, cancelling and forgetting their work."
  @spec reset() :: :ok
  def reset do
    Enum.each([Beamlens.Coordinator, Beamlens.Operator.Supervisor], fn child_id ->
      case Supervisor.terminate_child(Beamlens.Supervisor, child_id) do
        :ok -> :ok
        {:error, :not_found} -> :ok
      end
    end)

    Enum.each([Beamlens.Operator.Supervisor, Beamlens.Coordinator], fn child_id ->
      case Supervisor.restart_child(Beamlens.Supervisor, child_id) do
        {:ok, _} -> :ok
        {:ok, _, _} -> :ok
        {:error, :running} -> :ok
        {:error, :not_found} -> :ok
      end
    end)

    :ok
  catch
    :exit, _ -> :ok
  end

  @impl Supervisor
  def init(opts) do
    registry = Keyword.fetch!(opts, :client_registry)
    skill = Keyword.get(opts, :skill, Skill)
    :persistent_term.put({Beamlens.Supervisor, :skills}, [skill])

    children = [
      {Task.Supervisor, name: Beamlens.TaskSupervisor},
      {Registry, keys: :unique, name: Beamlens.OperatorRegistry},
      Beamlens.Skill.Logger.LogStore,
      {Beamlens.Coordinator,
       name: Beamlens.Coordinator,
       skills: [skill],
       max_iterations: @max_iterations,
       client_registry: registry},
      {Beamlens.Operator.Supervisor,
       skills: [[skill: skill, max_iterations: @max_iterations]], client_registry: registry}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
