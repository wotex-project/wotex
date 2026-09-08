defmodule Wotex.Lab.Test.BadStartComponent do
  @moduledoc false

  @behaviour Wotex.Lab.Plugin
  @behaviour Wotex.Lab.Component

  @impl Wotex.Lab.Plugin
  def id, do: "bad-start"

  @impl Wotex.Lab.Plugin
  def capabilities, do: ["bad.start"]

  @impl Wotex.Lab.Plugin
  def child_specs(config) do
    case Keyword.fetch!(config, :failure) do
      :invalid -> :not_a_list
      :raise -> raise "child specs raised"
      :throw -> throw(:child_specs_threw)
    end
  end

  @impl Wotex.Lab.Plugin
  def manifest do
    %{
      "id" => id(),
      "version" => "1.0.0",
      "capabilities" => capabilities(),
      "package" => "wotex_lab",
      "behaviours" => ["Wotex.Lab.Plugin", "Wotex.Lab.Component"],
      "configuration" => %{"failure" => "invalid | raise | throw"},
      "ownership" => %{"children" => "none"},
      "limits" => %{"children_per_attempt" => 0},
      "fixtures" => [],
      "evidence" => ["test/wotex/lab/runner_test.exs"],
      "cleanup" => %{"contract" => "none"},
      "instance_scope" => "per_instance",
      "dependencies" => %{}
    }
  end

  @impl Wotex.Lab.Component
  def execute(_operation, _input, _context), do: {:ok, nil}
end
