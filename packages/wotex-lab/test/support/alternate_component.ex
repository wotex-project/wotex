defmodule Wotex.Lab.Test.AlternateComponent do
  @moduledoc false

  @behaviour Wotex.Lab.Plugin
  @behaviour Wotex.Lab.Component

  @impl Wotex.Lab.Plugin
  def id, do: "room"

  @impl Wotex.Lab.Plugin
  def capabilities, do: ["alternate.read"]

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
      "ownership" => %{},
      "limits" => %{},
      "fixtures" => [],
      "evidence" => ["test/wotex/lab/runner_test.exs"],
      "cleanup" => %{},
      "instance_scope" => "per_instance",
      "dependencies" => %{}
    }
  end

  @impl Wotex.Lab.Component
  def execute(_, input, _), do: {:ok, input}
end
