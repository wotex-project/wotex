defmodule WotexLabWorkbench.ReleaseConfigurationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  @tag :tmp_dir
  test "production assets resolve from the application when the working directory changes", %{
    tmp_dir: directory
  } do
    runtime = Path.expand("../../config/runtime.exs", __DIR__)

    script = ~S'''
    config = Config.Reader.read!(hd(System.argv()), env: :prod, target: :host)
    assets = Keyword.fetch!(config, :phoenix_assets)
    root = Keyword.fetch!(assets, :static_root)
    manifest = assets |> Keyword.fetch!(:build) |> Keyword.fetch!(:vite_manifest)
    true = root == Application.app_dir(:wotex_lab_workbench, "priv/static")
    true = Path.type(manifest) == :absolute
    true = manifest == Path.join(root, ".vite/manifest.json")
    true = File.regular?(manifest)
    IO.puts("relocated production assets: passed")
    '''

    environment =
      for {name, _} <- System.get_env(), String.starts_with?(name, "WOTEX_LAB_"), do: {name, nil}

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["-pa", Application.app_dir(:wotex_lab_workbench, "ebin"), "-e", script, runtime],
        cd: directory,
        env:
          environment ++
            [{"SECRET_KEY_BASE", String.duplicate("r", 64)}, {"PORT", "4000"}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "relocated production assets: passed"
  end
end
