defmodule Wotex.Lab.Test.RoomComponent do
  @moduledoc false

  # A trusted host component for runner tests: starts one loopback Reference
  # Thing per attempt and executes typed steps against it through the runtime.

  @behaviour Wotex.Lab.Plugin
  @behaviour Wotex.Lab.Component

  alias Wotex.Lab.Adapters.Runtime.{Loopback, NoSec}
  alias Wotex.Lab.Error
  alias Wotex.Lab.Reference.Thing
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context}
  alias Wotex.ThingDescription

  @impl Wotex.Lab.Plugin
  def id, do: "room"

  @impl Wotex.Lab.Plugin
  def capabilities, do: ["room.read", "room.act", "room.util"]

  @impl Wotex.Lab.Plugin
  def child_specs(config) do
    attempt_id = Keyword.fetch!(config, :attempt_id)

    case Keyword.get(config, :startup, :thing) do
      :fail ->
        [broken_spec(attempt_id)]

      :partial ->
        [probe_spec(config), broken_spec(attempt_id)]

      :two ->
        [probe_spec(config), probe_spec(config)]

      :thing ->
        {:ok, td} =
          Application.app_dir(:wotex_lab, "priv/fixtures/loopback/thing-description.json")
          |> File.read!()
          |> ThingDescription.parse()

        [
          Supervisor.child_spec(
            {Thing,
             td: td,
             state: %{
               "temperature" => Keyword.get(config, :temperature, 20.0),
               "target" => 21.0
             },
             tokens: %{"bearer_sc" => "t"}},
            id: {Thing, attempt_id},
            restart: :temporary
          )
        ]
    end
  end

  @impl Wotex.Lab.Plugin
  def manifest,
    do: %{
      "id" => "room",
      "version" => "1.0.0",
      "capabilities" => capabilities(),
      "package" => "wotex_lab",
      "behaviours" => ["Wotex.Lab.Plugin", "Wotex.Lab.Component"],
      "configuration" => %{"temperature" => "number"},
      "ownership" => %{"children" => "one loopback Reference Thing per attempt"},
      "limits" => %{"children_per_attempt" => 2},
      "fixtures" => ["loopback/thing-description.json"],
      "evidence" => ["test/wotex/lab/runner_test.exs"],
      "cleanup" => %{"contract" => "runner-owned bounded termination"},
      "instance_scope" => "per_instance",
      "dependencies" => %{"wotex_runtime" => "0.1.0"}
    }

  def broken_start, do: {:error, :component_refused}

  @impl Wotex.Lab.Component
  def execute("read", %{"property" => property}, %{children: [thing | _]} = context)
      when is_binary(property) do
    with {:ok, consumed} <- consumed(thing),
         {:ok, result} <-
           ConsumedThing.read_property(
             consumed,
             property,
             Context.new!(request_id: context.step_id, deadline: deadline(context))
           ) do
      {:ok, result.payload}
    end
  end

  def execute("invoke", %{"action" => action, "input" => input}, %{children: [thing | _]} = context) do
    with {:ok, consumed} <- consumed(thing),
         {:ok, result} <-
           ConsumedThing.invoke_action(
             consumed,
             action,
             input,
             Context.new!(request_id: context.step_id, deadline: deadline(context))
           ) do
      {:ok, %{"status" => Atom.to_string(result.status)}}
    end
  end

  def execute("echo", input, _), do: {:ok, input}
  def execute("seed", _, context), do: {:ok, context.seed}
  def execute("sum", _, context), do: {:ok, context.results |> Map.values() |> Enum.sum()}

  def execute("sleep", ms, _) when is_integer(ms) do
    Process.sleep(ms)
    {:ok, ms}
  end

  def execute("big", bytes, _) when is_integer(bytes), do: {:ok, :binary.copy("x", bytes)}

  def execute("write", name, context) do
    :ok = File.write(Path.join(context.work_dir, name), "scratch")
    {:ok, name}
  end

  def execute("bad", _, _), do: :not_a_result

  def execute("fail", _, _),
    do: {:error, Error.new(:step_failed, :running, "step failed on request")}

  def execute(operation, _, _),
    do:
      {:error,
       Error.new(:unknown_operation, :running, "unknown operation",
         details: %{operation: operation}
       )}

  defp consumed(thing) do
    with {:ok, profile} <-
           BindingProfile.new(
             id: :loopback,
             schemes: ["loopback"],
             operations: Wotex.Runtime.operations()
           ) do
      ConsumedThing.new(Thing.thing_description(thing),
        profiles: [profile],
        transports: %{loopback: {Loopback, %{host: thing}}},
        credentials: {NoSec, %{}}
      )
    end
  end

  defp deadline(context), do: System.monotonic_time(:millisecond) + context.remaining_ms

  defp probe_spec(config) do
    receiver = Keyword.get(config, :receiver)

    Supervisor.child_spec(
      {Agent,
       fn ->
         if is_pid(receiver), do: send(receiver, {:probe_started, self()})
         :started
       end},
      restart: :temporary
    )
  end

  defp broken_spec(attempt_id) do
    %{
      id: {:broken, attempt_id},
      start: {__MODULE__, :broken_start, []},
      restart: :temporary
    }
  end
end
