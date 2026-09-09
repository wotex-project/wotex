defmodule Wotex.Lab.Test.InvalidPluginComponent do
  @moduledoc false

  @behaviour Wotex.Lab.Plugin
  @behaviour Wotex.Lab.Component

  @impl Wotex.Lab.Plugin
  def id, do: "Invalid Plugin"

  @impl Wotex.Lab.Plugin
  def capabilities, do: ["invalid.plugin"]

  @impl Wotex.Lab.Plugin
  def child_specs(_), do: []

  @impl Wotex.Lab.Plugin
  def manifest, do: %{}

  @impl Wotex.Lab.Component
  def execute(_, input, _), do: {:ok, input}
end
