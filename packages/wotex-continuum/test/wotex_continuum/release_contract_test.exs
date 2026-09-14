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
    assert project[:source_url] == "https://github.com/wotex-project/wotex-continuum"
    assert project[:homepage_url] == "https://wotex.io"
    assert WotexContinuum.schema_version() == "2.0.0"

    assert package[:name] == "wotex_continuum"
    assert package[:licenses] == ["Apache-2.0"]
    assert package[:maintainers] == ["Tobias Bohwalli <hi@futhr.io>"]

    assert package[:links] == %{
             "Documentation" => "https://hexdocs.pm/wotex_continuum",
             "GitHub" => "https://github.com/wotex-project/wotex-continuum",
             "Project" => "https://wotex.io",
             "W3C Web of Things" => "https://www.w3.org/WoT/"
           }

    assert Enum.member?(package[:files], "lib")
    assert Enum.member?(package[:files], "specs")
    assert Enum.member?(package[:files], "priv/schemas")
    assert Enum.member?(package[:files], "test/vectors")
  end
end
