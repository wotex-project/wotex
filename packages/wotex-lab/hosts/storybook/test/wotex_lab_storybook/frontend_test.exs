defmodule WotexLabStorybook.FrontendTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "the actual live host inherits the frontend plugins and accepts arrow operations" do
    host = Path.expand("../..", __DIR__)
    static = Application.fetch_env!(:wotex_lab_storybook, :workbench_static)
    script = Path.expand("../../tools/lint/biome-host.ts", static)
    relative = "priv/static/contract-assets/style-probe-#{System.unique_integer([:positive])}.js"
    path = Path.join(host, relative)
    on_exit(fn -> File.rm(path) end)

    for {source, accepted?} <- [{"class State {}\n", false}, {"const save = () => 1\n", true}] do
      File.write!(path, source)

      {output, status} =
        System.cmd(
          "node",
          ["--experimental-strip-types", script, host, "lint", "--only=plugin", relative],
          cd: host,
          env: environment(),
          stderr_to_stdout: true
        )

      if accepted? do
        assert status == 0, output
      else
        assert status != 0
        assert output =~ "factory function", output
      end
    end
  end

  test "the shipped bridge preserves lazy loading and per-mount lifecycle receivers" do
    host = Path.expand("../..", __DIR__)
    static = Application.fetch_env!(:wotex_lab_storybook, :workbench_static)
    aliases = Path.expand("../../bin/register_aliases.ts", static)

    {output, status} =
      System.cmd(
        "node",
        [
          "--experimental-strip-types",
          "--import",
          aliases,
          "--test",
          "test/frontend/storybook-bridge.test.ts"
        ],
        cd: host,
        env: environment(),
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  defp environment do
    System.get_env()
    |> Map.new(fn {key, _} -> {key, nil} end)
    |> Map.put("PATH", System.fetch_env!("PATH"))
    |> Map.to_list()
  end
end
