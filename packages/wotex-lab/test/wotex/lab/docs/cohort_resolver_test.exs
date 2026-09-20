defmodule Wotex.Lab.Docs.CohortResolverTest do
  use ExUnit.Case, async: true

  alias Wotex.Lab.Docs.{Catalogue, CohortResolver}
  alias Wotex.Lab.Test.ChildEnvironment

  test "rolling resolution freezes each repository head once and renews every tree identity" do
    {:ok, catalogue} = Catalogue.load()
    {wotex, dot} = fixture_repositories(catalogue)

    overrides = %{
      "https://github.com/wotex-project/wotex" => wotex,
      "https://github.com/wotex-project/.github" => dot
    }

    assert {:ok, resolved} =
             CohortResolver.resolve(catalogue, "rolling", repository_overrides: overrides)

    assert resolved["profile"] == "rolling"
    assert :ok = Catalogue.validate(resolved)
    wotex_revision = revision(wotex)
    dot_revision = revision(dot)

    assert Enum.all?(resolved["sources"], fn source ->
             expected = if source["id"] == "wotex-dot", do: dot_revision, else: wotex_revision

             source["revision"] == expected and
               source["expected_collection_digest"] == nil and
               String.starts_with?(source["tree_digest"], "sha256:")
           end)
  end

  test "release resolution accepts the lock and refuses unlocked or differently labelled catalogues" do
    {:ok, catalogue} = Catalogue.load()
    assert {:ok, ^catalogue} = CohortResolver.resolve(catalogue, "release")

    [first | rest] = catalogue["sources"]
    unlocked = %{catalogue | "sources" => [%{first | "expected_collection_digest" => nil} | rest]}

    assert {:error, {:unlocked_documentation_source, "wotex"}} =
             CohortResolver.resolve(unlocked, "release")

    rolling = Map.put(catalogue, "profile", "rolling")

    assert {:error, {:documentation_profile_mismatch, "rolling", "release"}} =
             CohortResolver.resolve(rolling, "release")
  end

  defp fixture_repositories(catalogue) do
    sources = catalogue["sources"]

    wotex_sources =
      Enum.filter(sources, &(&1["repository_url"] == "https://github.com/wotex-project/wotex"))

    dot_sources =
      Enum.filter(sources, &(&1["repository_url"] == "https://github.com/wotex-project/.github"))

    {fixture_repository(wotex_sources), fixture_repository(dot_sources)}
  end

  defp fixture_repository(sources) do
    root = Path.join(System.tmp_dir!(), "wotex-doc-resolver-#{token()}")
    File.mkdir!(root)

    sources
    |> Enum.flat_map(& &1["documentation_roots"])
    |> Enum.uniq()
    |> Enum.each(&write_root(root, &1))

    git!(root, ["init", "--quiet", "--initial-branch=main"])
    git!(root, ["config", "user.name", "Fixture"])
    git!(root, ["config", "user.email", "fixture@example.invalid"])
    git!(root, ["add", "."])
    git!(root, ["commit", "--quiet", "-m", "fixture"])
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp write_root(root, path) do
    target = Path.join(root, path)

    if Path.extname(path) == ".md" do
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, "# #{Path.basename(path)}\n")
    else
      File.mkdir_p!(target)
      File.write!(Path.join(target, "source.md"), "# Source\n")
    end
  end

  defp revision(repository),
    do: git!(repository, ["rev-parse", "HEAD"]) |> String.trim()

  defp git!(repository, args) do
    case System.cmd("git", ["-C", repository | args],
           stderr_to_stdout: true,
           env: ChildEnvironment.scrubbed()
         ) do
      {output, 0} -> output
      {output, status} -> flunk("git failed with #{status}: #{output}")
    end
  end

  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
end
