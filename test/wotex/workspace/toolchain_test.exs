defmodule Wotex.Workspace.ToolchainTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace
  alias Wotex.Workspace.Manifest

  # The `[tools]` table of mise.toml as a map. The file holds only quoted
  # `key = "value"` pairs, so a line reader is enough.
  defp mise_tools do
    Workspace.root()
    |> Path.join("mise.toml")
    |> File.read!()
    |> String.split("\n")
    |> Enum.reduce({nil, %{}}, fn line, {section, tools} ->
      line = String.trim(line)

      cond do
        String.starts_with?(line, "[") ->
          {String.trim(String.trim(line, "["), "]"), tools}

        section == "tools" and line =~ ~r/^"?[^"=]+"?\s*=\s*"[^"]*"$/ ->
          [key, value] = String.split(line, "=", parts: 2)
          {section, Map.put(tools, trim_quotes(key), trim_quotes(value))}

        true ->
          {section, tools}
      end
    end)
    |> elem(1)
  end

  defp trim_quotes(text), do: String.trim(String.trim(text), "\"")

  test "mise.toml pins the current lane of tooling/packages.yaml and Dexter" do
    {:ok, current} = Manifest.lane("current", Manifest.load!())
    tools = mise_tools()

    assert tools["erlang"] == current.otp
    assert tools["elixir"] == current.elixir
    assert tools["aqua:remoteoss/dexter"] =~ ~r/^\d+\.\d+\.\d+$/
  end

  test "mise.toml replaces .tool-versions and selects every package when it changes" do
    refute File.exists?(Path.join(Workspace.root(), ".tool-versions"))
    assert "mise.toml" in Manifest.load!().select_all_on
  end

  test "the Dexter index is ignored" do
    ignored = File.read!(Path.join(Workspace.root(), ".gitignore"))
    assert ".dexter/" in String.split(ignored, "\n")
  end
end
