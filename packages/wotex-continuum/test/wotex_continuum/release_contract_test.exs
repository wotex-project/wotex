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
             "Documentation" => "https://hexdocs.pm/wotex_continuum",
             "GitHub" => "https://github.com/wotex-project/wotex",
             "Project" => "https://wotex.io",
             "Specifications" =>
               "https://github.com/wotex-project/wotex/tree/main/docs/packages/wotex-continuum",
             "W3C Web of Things" => "https://www.w3.org/WoT/"
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
end
