defmodule Wotex.Lab.Test.RaisingPluginComponent do
  @moduledoc false

  @behaviour Wotex.Lab.Plugin
  @behaviour Wotex.Lab.Component

  @impl Wotex.Lab.Plugin
  def id, do: raise("inspection failed")

  @impl Wotex.Lab.Plugin
  def capabilities, do: ["raising.plugin"]

  @impl Wotex.Lab.Plugin
  def child_specs(_config), do: []

  @impl Wotex.Lab.Plugin
  def manifest, do: %{}

  @impl Wotex.Lab.Component
  def execute(_operation, input, _context), do: {:ok, input}
end
