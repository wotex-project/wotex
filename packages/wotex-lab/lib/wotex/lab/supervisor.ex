defmodule Wotex.Lab.Supervisor do
  @moduledoc """
  A caller-owned supervision tree with isolated Thing and session children.

  Child supervisors are anonymous and resolved through the supplied instance
  PID. No Registry, generated atom, global environment or shared store is used.
  Trusted child specs retain their own shutdown and restart semantics.

  The root uses `:one_for_one` supervision and owns distinct dynamic
  supervisors for `:things` and `:sessions`. Failure or restart of one role
  does not restart the other role's children; stopping the root terminates both
  roles and their descendants. Capacity is enforced independently for each
  role.

  Startup requires a bounded string `:id` and accepts an optional OTP
  registration `:name` and `:max_children`. The module validates configuration
  before initialization, reports unavailable role supervisors explicitly, and
  passes native `DynamicSupervisor` child results to the caller.
  """

  use Supervisor

  alias Wotex.Lab.{Error, Options}

  @doc "Builds a child spec; malformed configuration raises `ArgumentError` before startup."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    case validate(opts) do
      :ok ->
        %{
          id: {__MODULE__, Keyword.fetch!(opts, :id)},
          start: {__MODULE__, :start_link, [opts]},
          type: :supervisor
        }

      {:error, error} ->
        raise ArgumentError, error.message
    end
  end

  @doc "Starts an isolated instance; the default capacity is 128 children per role."
  @spec start_link(keyword()) :: Supervisor.on_start() | {:error, Error.t()}
  def start_link(opts) do
    with :ok <- validate(opts) do
      Supervisor.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
    end
  end

  @doc "Places a child under `:things` or `:sessions` in the supplied live instance."
  @spec start_child(pid(), :things | :sessions, Supervisor.child_spec() | {module(), term()}) ::
          DynamicSupervisor.on_start_child() | {:error, Error.t()}
  def start_child(instance, role, child) when role in [:things, :sessions] do
    case List.keyfind(Supervisor.which_children(instance), role, 0) do
      {^role, pid, :supervisor, _} when is_pid(pid) ->
        DynamicSupervisor.start_child(pid, child)

      _ ->
        {:error, Error.new(:supervisor_unavailable, :composition, "child supervisor unavailable")}
    end
  end

  def start_child(_, _, _),
    do: {:error, Error.new(:unknown_role, :composition, "role must be things or sessions")}

  @doc "Terminates a child of the instance's Thing or session supervisor; the child is not restarted."
  @spec stop_child(pid(), :things | :sessions, pid()) :: :ok | {:error, Error.t() | :not_found}
  def stop_child(instance, role, child) when role in [:things, :sessions] and is_pid(child) do
    case List.keyfind(Supervisor.which_children(instance), role, 0) do
      {^role, pid, :supervisor, _} when is_pid(pid) ->
        DynamicSupervisor.terminate_child(pid, child)

      _ ->
        {:error, Error.new(:supervisor_unavailable, :composition, "child supervisor unavailable")}
    end
  end

  def stop_child(_, _, _),
    do: {:error, Error.new(:unknown_role, :composition, "role must be things or sessions")}

  @impl Supervisor
  def init(opts) do
    children =
      for role <- [:things, :sessions] do
        Supervisor.child_spec(
          {DynamicSupervisor,
           strategy: :one_for_one, max_children: Keyword.get(opts, :max_children, 128)},
          id: role
        )
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp validate(opts) do
    with :ok <- Options.validate(opts, [:id, :name, :max_children]) do
      if Options.identifier?(Keyword.get(opts, :id)) and
           valid_capacity?(Keyword.get(opts, :max_children, 128)) and
           valid_name?(Keyword.get(opts, :name)) do
        :ok
      else
        {:error, Error.new(:invalid_instance, :construction, "instance configuration is invalid")}
      end
    end
  end

  defp valid_capacity?(capacity), do: is_integer(capacity) and capacity in 1..10_000
  defp valid_name?(nil), do: true
  defp valid_name?(name) when is_atom(name), do: true
  defp valid_name?({:global, _}), do: true
  defp valid_name?({:via, module, _}) when is_atom(module), do: true
  defp valid_name?(_), do: false
end
