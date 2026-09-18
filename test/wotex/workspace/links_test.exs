defmodule Wotex.Workspace.LinksTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.Links
  alias WotexWorkspace.Fixtures

  @guide """
  # Guide

  See [the README](../README.md), [the spec](specs/a.md#section) and
  ![a diagram](img/flow%20chart.svg "Flow").
  Broken: [missing](missing.md) and [gone](../nowhere/x.md#top).
  Skipped: [site](https://example.org/x.md), [mail](mailto:a@example.org),
  [anchor](#local), `[code](not-a-link.md)` and [angle](<specs/a.md>).
  Directory: [specs](specs/) and root-relative [license](/LICENSE).

  ```elixir
  # [fenced](fenced-missing.md)
  ```

  [ref]: specs/a.md
  [dead]: specs/dead.md "Title"
  [^note]: not a link target.md
  """

  setup context do
    root = Fixtures.tmp_dir(context)
    Fixtures.write!(root, "README.md", "[guide](docs/guide.md)\n[bad](docs/none.md)\n")
    Fixtures.write!(root, "LICENSE", "license\n")
    Fixtures.write!(root, "docs/guide.md", @guide)
    Fixtures.write!(root, "docs/specs/a.md", "# A\n")
    Fixtures.write!(root, "docs/img/flow chart.svg", "<svg/>")
    %{root: root}
  end

  test "reports every broken relative link with its line", %{root: root} do
    broken = Links.check(root, ["README.md", "docs/guide.md", "docs/deleted.md"])

    assert Enum.map(broken, &Links.format/1) == [
             "README.md:2: docs/none.md",
             "docs/guide.md:5: missing.md",
             "docs/guide.md:5: ../nowhere/x.md#top",
             "docs/guide.md:15: specs/dead.md"
           ]

    assert Enum.all?(broken, &(&1.problem == :missing))
  end

  test "checks main-branch URLs of this repository against the working tree", %{root: root} do
    Fixtures.write!(root, "notes.md", """
    [ok](https://github.com/wotex-project/wotex/blob/main/docs/specs/a.md#part)
    [dir](https://github.com/wotex-project/wotex/tree/main/docs/specs)
    [gone](https://github.com/wotex-project/wotex/blob/main/docs/specs/gone.md)
    [old tree](https://github.com/wotex-project/wotex/tree/main/docs/old)
    [pinned](https://github.com/wotex-project/wotex/blob/0123abc/docs/gone.md)
    [other](https://github.com/elsewhere/wotex/blob/main/docs/gone.md)
    """)

    assert Enum.map(Links.check(root, ["notes.md"]), &Links.format/1) == [
             "notes.md:3: https://github.com/wotex-project/wotex/blob/main/docs/specs/gone.md",
             "notes.md:4: https://github.com/wotex-project/wotex/tree/main/docs/old"
           ]
  end

  test "package documentation may not link relatively to Markdown outside the package",
       %{root: root} do
    Fixtures.write!(root, "docs/packages/alpha/specs/A.01.md", "# A.01\n")
    Fixtures.write!(root, "docs/packages/beta/README.md", "# Beta\n")

    Fixtures.write!(
      root,
      "packages/alpha/README.md",
      "# Alpha\n[spec](../../docs/packages/alpha/specs/A.01.md)\n"
    )

    Fixtures.write!(root, "packages/alpha/lib/alpha.ex", "")

    Fixtures.write!(root, "docs/packages/alpha/plans/plan.md", """
    [own spec](../specs/A.01.md) and [own code](../../../../packages/alpha/lib/alpha.ex)
    [own readme](../../../../packages/alpha/README.md)
    [sibling](../../beta/README.md#intro) and [root](../../../../README.md)
    [licence](../../../../LICENSE) and [url](https://github.com/wotex-project/wotex/blob/main/README.md)
    """)

    Fixtures.write!(root, "packages/beta/README.md", "[family](../../README.md)\n")
    Fixtures.write!(root, "packages/beta/CHANGELOG.md", "[family](../../README.md)\n")

    files = [
      "docs/packages/alpha/plans/plan.md",
      "packages/alpha/README.md",
      "packages/beta/README.md",
      "packages/beta/CHANGELOG.md",
      "docs/guide.md"
    ]

    crossing = Enum.reject(Links.check(root, files), &(&1.problem == :missing))

    assert Enum.map(crossing, &Links.format/1) == [
             "docs/packages/alpha/plans/plan.md:3: ../../beta/README.md#intro leaves the " <>
               "package documentation; link " <>
               "https://github.com/wotex-project/wotex/blob/main/docs/packages/beta/README.md",
             "docs/packages/alpha/plans/plan.md:3: ../../../../README.md leaves the package " <>
               "documentation; link https://github.com/wotex-project/wotex/blob/main/README.md",
             "packages/beta/README.md:1: ../../README.md leaves the package documentation; " <>
               "link https://github.com/wotex-project/wotex/blob/main/README.md"
           ]
  end

  test "published_package/1 names the package whose HexDocs publish a file" do
    assert Links.published_package("docs/packages/alpha/specs/A.01.md") == "alpha"
    assert Links.published_package("docs/packages/alpha/README.md") == "alpha"
    assert Links.published_package("packages/alpha/README.md") == "alpha"
    assert Links.published_package("packages/alpha/CHANGELOG.md") == nil
    assert Links.published_package("docs/packages/README.md") == nil
    assert Links.published_package("docs/guide.md") == nil
  end

  test "links/1 skips fenced code and inline code spans" do
    targets = Enum.map(Links.links(@guide), &elem(&1, 1))

    assert "../README.md" in targets
    assert "<specs/a.md>" in targets
    refute "fenced-missing.md" in targets
    refute "not-a-link.md" in targets
    refute Enum.any?(targets, &String.contains?(&1, "not a link"))
  end

  test "resolve/2 strips anchors and skips external targets" do
    assert Links.resolve("docs/guide.md", "specs/a.md#x") == {:relative, "docs/specs/a.md"}
    assert Links.resolve("docs/guide.md", "../README.md") == {:relative, "README.md"}
    assert Links.resolve("docs/guide.md", "/LICENSE") == {:relative, "LICENSE"}
    assert Links.resolve("README.md", "./docs/./guide.md?plain=1") == {:relative, "docs/guide.md"}

    assert Links.resolve("docs/guide.md", "img/flow%20chart.svg") ==
             {:relative, "docs/img/flow chart.svg"}

    assert Links.resolve("x.md", "https://github.com/wotex-project/wotex/blob/main/a/b.md#c") ==
             {:repository, "a/b.md"}

    assert Links.resolve("x.md", "https://github.com/wotex-project/wotex/tree/main/docs") ==
             {:repository, "docs"}

    assert Links.resolve("docs/guide.md", "#local") == :skip
    assert Links.resolve("docs/guide.md", "https://example.org") == :skip
    assert Links.resolve("docs/guide.md", "https://github.com/wotex-project/wotex/pulls") == :skip
    assert Links.resolve("docs/guide.md", "mailto:a@example.org") == :skip
  end

  test "tracked_markdown/1 lists the Markdown files Git tracks", %{root: root} do
    {_output, 0} = System.cmd("git", ["init", "-q"], cd: root, env: [])
    {_output, 0} = System.cmd("git", ["add", "README.md", "docs/guide.md"], cd: root, env: [])
    assert Links.tracked_markdown(root) == {:ok, ["README.md", "docs/guide.md"]}
  end
end
