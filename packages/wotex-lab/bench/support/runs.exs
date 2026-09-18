defmodule Wotex.Lab.Bench.Runs do
  @moduledoc false

  # Chained scenario definitions for the runner benchmark. Every step echoes a
  # small reading and depends on the step before it, the shape of the admitted
  # cookbook scenarios; one assertion checks every step's value and the
  # definition pins one packaged fixture by digest, as a cookbook scenario does.

  alias Wotex.Lab.Bench.EchoComponent
  alias Wotex.Lab.Evidence.Digest
  alias Wotex.Lab.Runner.{Definition, Host}
  alias Wotex.Lab.Scenario

  @id "bench-chain"
  @capability "bench.echo"
  @fixture "thermal/thing-description.json"

  @spec sizes() :: %{String.t() => pos_integer()}
  def sizes, do: %{"4 steps" => 4, "16 steps" => 16, "100 steps" => 100}

  @spec work_root() :: Path.t()
  def work_root, do: Path.join(System.tmp_dir!(), "wotex-lab-bench-runs")

  @spec host(pid()) :: Host.t()
  def host(lab) do
    {:ok, host} = Host.new(modules: [EchoComponent], instance: lab, work_root: work_root())
    host
  end

  @spec input(pos_integer(), Host.t()) :: map()
  def input(count, host) do
    scenario_options = scenario_options(count)
    definition_options = definition_options(count)
    {:ok, scenario} = Scenario.new(scenario_options)
    {:ok, definition} = Definition.new(definition_options)

    %{
      count: count,
      scenario_options: scenario_options,
      definition_options: definition_options,
      scenario: scenario,
      definition: definition,
      host: host
    }
  end

  defp scenario_options(count) do
    [id: @id, title: "Chained echo steps", capabilities: [@capability], seed: 7, max_steps: count]
  end

  defp definition_options(count) do
    fixture = Application.app_dir(:wotex_lab, Path.join("priv/fixtures", @fixture))

    [
      id: @id,
      revision: "bench-v1",
      fixtures: %{@fixture => Digest.file!(fixture)},
      capabilities: [@capability],
      steps: Enum.map(1..count, &step/1),
      assertions: Enum.map(1..count, &assertion/1)
    ]
  end

  defp step(index) do
    %{
      "id" => step_id(index),
      "capability" => @capability,
      "operation" => "echo",
      "input" => %{"index" => index, "reading" => 20.0 + index / 10},
      "depends_on" => if(index == 1, do: [], else: [step_id(index - 1)])
    }
  end

  defp assertion(index) do
    %{"id" => "value-#{index}", "step" => step_id(index), "key" => "index", "equals" => index}
  end

  defp step_id(index), do: "step-#{index}"
end
