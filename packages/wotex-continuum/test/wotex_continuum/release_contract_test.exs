defmodule WotexContinuum.ReleaseContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "package and wire identities remain independent and package metadata is public" do
    project = Mix.Project.config()
    package = Keyword.fetch!(project, :package)

    assert project[:app] == :wotex_continuum
    assert project[:version] == "0.1.0"
    assert project[:elixir] == "~> 1.18"
    assert project[:name] == "Wotex Continuum"
    assert project[:source_url] == "https://github.com/wotex-project/wotex"
    assert project[:homepage_url] == "https://wotex.io"
    assert WotexContinuum.schema_version() == "2.0.0"

    assert package[:name] == "wotex_continuum"
    assert package[:licenses] == ["Apache-2.0"]
    assert package[:maintainers] == ["Tobias Bohwalli <hi@futhr.io>"]

    assert package[:links] == %{
             "Changelog" =>
               "https://github.com/wotex-project/wotex/blob/main/packages/wotex-continuum/CHANGELOG.md",
             "GitHub" => "https://github.com/wotex-project/wotex",
             "Specifications" =>
               "https://github.com/wotex-project/wotex/tree/main/docs/packages/wotex-continuum"
           }

    assert Enum.member?(package[:files], "lib")
    assert Enum.member?(package[:files], "priv/schemas")
    assert Enum.member?(package[:files], "priv/vectors")
    refute Enum.any?(package[:files], &String.starts_with?(&1, "test"))

    # Markdown documentation reaches consumers through HexDocs, not the archive.
    refute Enum.any?(package[:files], &String.starts_with?(&1, "docs"))
    refute Enum.member?(package[:files], "specs")
    refute Enum.member?(package[:files], "provenance")
  end

  test "the workspace dependency switch is refused outside development, test and docs" do
    project = Path.expand("../..", __DIR__)

    for {env, message} <- [
          {[{"WOTEX_PATH_DEPS", "1"}, {"MIX_ENV", "prod"}],
           "WOTEX_PATH_DEPS is allowed only in development, test or docs"},
          {[{"WOTEX_PATH_DEPS", "true"}, {"MIX_ENV", "test"}],
           "WOTEX_PATH_DEPS must be unset or equal to 1"}
        ] do
      assert {output, status} =
               System.cmd("mix", ["help"], cd: project, env: env, stderr_to_stdout: true)

      assert status != 0
      assert output =~ message
    end
  end
end
