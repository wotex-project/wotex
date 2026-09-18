defmodule Wotex.Lab.Bench.EchoComponent do
  @moduledoc false

  # A trusted host component for the runner benchmark. It starts no child and
  # answers each `echo` step with its input and the number of dependency
  # values the runner passed in, so the measured work is the runner's own.

  @behaviour Wotex.Lab.Component
  @behaviour Wotex.Lab.Plugin

  @impl Wotex.Lab.Plugin
  def id, do: "bench-echo"

  @impl Wotex.Lab.Plugin
  def capabilities, do: ["bench.echo"]

  @impl Wotex.Lab.Plugin
  def child_specs(_), do: []

  @impl Wotex.Lab.Plugin
  def manifest do
    %{
      "id" => id(),
      "version" => "1.0.0",
      "capabilities" => capabilities(),
      "package" => "wotex_lab",
      "behaviours" => ["Wotex.Lab.Plugin", "Wotex.Lab.Component"],
      "configuration" => %{},
      "ownership" => %{"children" => "none"},
      "limits" => %{"children_per_attempt" => 0},
      "fixtures" => [],
      "evidence" => [],
      "cleanup" => %{"contract" => "runner-owned work directory only"},
      "instance_scope" => "per_instance",
      "dependencies" => %{}
    }
  end

  @impl Wotex.Lab.Component
  def execute("echo", input, context) when is_map(input),
    do: {:ok, Map.put(input, "dependencies", map_size(context.results))}
end
