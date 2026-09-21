defmodule Wotex.Lab.Docs.RepositoryOverridesTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Docs.RepositoryOverrides

  @url "https://github.com/wotex-project/wotex"
  @profile "https://github.com/wotex-project/.github"
  @catalogue %{"sources" => [%{"repository_url" => @url}, %{"repository_url" => @profile}]}

  @tag :tmp_dir
  test "offline admission requires one local source for every repository", %{tmp_dir: root} do
    package = Path.join(root, "wotex")
    profile = Path.join(root, "profile")
    File.mkdir!(package)
    File.mkdir!(profile)

    assert {:ok, overrides} =
             RepositoryOverrides.admit(
               @catalogue,
               ["#{@url}=#{package}", "#{@profile}=#{profile}"],
               true
             )

    assert overrides == %{@url => package, @profile => profile}

    assert {:error, {:missing_documentation_repositories, [@profile]}} =
             RepositoryOverrides.admit(@catalogue, ["#{@url}=#{package}"], true)

    assert {:ok, %{@url => ^package}} =
             RepositoryOverrides.admit(@catalogue, ["#{@url}=#{package}"], false)
  end

  @tag :tmp_dir
  test "unknown, duplicate, absent and malformed sources fail closed", %{tmp_dir: root} do
    File.mkdir!(Path.join(root, "source"))
    path = Path.join(root, "source")

    for values <- [
          ["https://example.test/repository=#{path}"],
          ["#{@url}=#{path}", "#{@url}=#{path}"],
          ["#{@url}=#{Path.join(root, "absent")}"],
          [@url],
          [nil]
        ] do
      assert {:error, {:invalid_documentation_repository_override, _}} =
               RepositoryOverrides.admit(@catalogue, values, false)
    end
  end
end
