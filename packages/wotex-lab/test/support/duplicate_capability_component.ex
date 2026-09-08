defmodule Wotex.Lab.Test.DuplicateCapabilityComponent do
  @moduledoc false

  @behaviour Wotex.Lab.Plugin
  @behaviour Wotex.Lab.Component

  @impl Wotex.Lab.Plugin
  def id, do: "duplicate-capability"

  @impl Wotex.Lab.Plugin
  def capabilities, do: ["room.util"]

  @impl Wotex.Lab.Plugin
  def child_specs(_config), do: []

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
  def execute(_operation, input, _context), do: {:ok, input}
end
