defmodule Wotex.Lab.Test.InvalidManifestComponent do
  @moduledoc false

  @behaviour Wotex.Lab.Plugin
  @behaviour Wotex.Lab.Component

  @impl Wotex.Lab.Plugin
  def id, do: "invalid-manifest"

  @impl Wotex.Lab.Plugin
  def capabilities, do: ["invalid.manifest"]

  @impl Wotex.Lab.Plugin
  def child_specs(_config), do: []

  @impl Wotex.Lab.Plugin
  def manifest, do: %{"id" => id(), "capabilities" => capabilities()}

  @impl Wotex.Lab.Component
  def execute(_operation, input, _context), do: {:ok, input}
end
