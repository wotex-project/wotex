defmodule Wotex.Workspace.ScaffoldTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace
  alias Wotex.Workspace.Catalogue
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Scaffold
  alias WotexWorkspace.Fixtures

  @manifest """
  schema_version: "1.0.0"
  lanes:
    current: { elixir: "1.20.2-otp-29", otp: "29.0.4" }
  select_all_on:
    - "mix.exs"
  packages:
    wotex:
      app: wotex
      depends_on: []
    wotex-runtime:
      app: wotex_runtime
      depends_on: [wotex]
  """

  setup context do
    root = Fixtures.tmp_dir(context)
    Fixtures.write!(root, "tooling/packages.yaml", @manifest)
    Fixtures.write!(root, "LICENSE", File.read!(Path.join(Workspace.root(), "LICENSE")))

    for file <- [".check.exs", ".doctor.exs", ".formatter.exs", "coveralls.json"] do
      source = Path.join([Workspace.root(), "packages/wotex-coap", file])
      Fixtures.write!(root, "packages/wotex-coap/#{file}", File.read!(source))
    end

    File.mkdir_p!(Path.join(root, "packages/wotex"))
    %{root: root}
  end

  test "creates the package, its documentation tree and the manifest entry", %{root: root} do
    assert {:ok, paths} =
             Scaffold.create("wotex-demo", root: root, depends_on: ["wotex", "wotex-runtime"])

    for relative <- ~w(
          packages/wotex-demo/mix.exs packages/wotex-demo/.check.exs
          packages/wotex-demo/.doctor.exs packages/wotex-demo/.formatter.exs
          packages/wotex-demo/coveralls.json packages/wotex-demo/config/config.exs
          packages/wotex-demo/CLAUDE.md packages/wotex-demo/README.md packages/wotex-demo/CHANGELOG.md
          packages/wotex-demo/LICENSE packages/wotex-demo/NOTICE packages/wotex-demo/lib/wotex/demo.ex
          packages/wotex-demo/test/test_helper.exs packages/wotex-demo/test/wotex/demo_test.exs
          packages/wotex-demo/bin/check_archive.exs packages/wotex-demo/bin/check_application_free.exs
          packages/wotex-demo/bin/check_boundary.exs
          docs/packages/wotex-demo/specs/catalogue.yaml docs/packages/wotex-demo/plans/wotex-demo-completion.md
          docs/packages/wotex-demo/provenance/.gitkeep tooling/packages.yaml
        ) do
      assert relative in paths, "#{relative} not reported"
      assert File.exists?(Path.join(root, relative)), "#{relative} not created"
    end

    for file <- ~w(.doctor.exs .formatter.exs coveralls.json) do
      assert File.read!(Path.join(root, "packages/wotex-demo/#{file}")) ==
               File.read!(Path.join(root, "packages/wotex-coap/#{file}"))
    end

    # Credo configuration is inherited from the repository root.
    refute File.exists?(Path.join(root, "packages/wotex-demo/.credo.exs"))

    # The standard full gate of the template package, without its native
    # tools, plus the boundary scan.
    gate = File.read!(Path.join(root, "packages/wotex-demo/.check.exs"))
    template = File.read!(Path.join(root, "packages/wotex-coap/.check.exs"))
    boundary = ~s|    {:boundary, command: "elixir bin/check_boundary.exs"},\n|
    native = ~r/\n    # First-party C.*\{:native_test,[^}]*\},/s
    assert String.replace(gate, boundary, "") == Regex.replace(native, template, "")
    refute gate =~ "native_"
    {config, _} = Code.eval_string(gate)
    tools = Keyword.fetch!(config, :tools)
    assert tools[:boundary] == [command: "elixir bin/check_boundary.exs"]
    assert tools[:ex_unit] == false
    assert tools[:coverage] == [command: "mix coveralls", env: %{"MIX_ENV" => "test"}]

    assert File.read!(Path.join(root, "packages/wotex-demo/LICENSE")) ==
             File.read!(Path.join(root, "LICENSE"))

    manifest = Manifest.load!(Path.join(root, "tooling/packages.yaml"))
    demo = Manifest.fetch!("wotex-demo", manifest)
    assert demo.app == "wotex_demo"
    assert demo.depends_on == ["wotex", "wotex-runtime"]
    assert Manifest.topological_order(manifest) == ~w(wotex wotex-runtime wotex-demo)

    mix_exs = File.read!(Path.join(root, "packages/wotex-demo/mix.exs"))
    assert {:ok, _} = Code.string_to_quoted(mix_exs)
    assert mix_exs =~ "defmodule Wotex.Demo.MixProject"
    assert mix_exs =~ "app: :wotex_demo"
    assert mix_exs =~ ~s|sibling(:wotex, "wotex")|
    assert mix_exs =~ ~s|sibling(:wotex_runtime, "wotex-runtime")|
    assert mix_exs =~ ~s|System.get_env("WOTEX_PATH_DEPS")|
    assert mix_exs =~ "if Mix.env() in [:dev, :test, :docs] do"

    assert mix_exs =~
             ~s|{app, path: Path.expand("../\#{directory}", __DIR__), env: :dev, override: true}|

    assert mix_exs =~ ~s|raise "WOTEX_PATH_DEPS is allowed only in development, test or docs"|
    assert mix_exs =~ ~s|package: "cmd env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build"|

    assert mix_exs =~
             ~s|files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE NOTICE)|

    assert mix_exs =~ ~s|@docs Path.expand("../../docs/packages/wotex-demo", __DIR__)|
    assert mix_exs =~ ~s|Path.wildcard("\#{@docs}/{specs,plans,decisions,provenance}/*.md")|
    assert mix_exs =~ ~s|source_ref: "wotex-demo-v\#{@version}"|
    assert mix_exs =~ "source_url_pattern: &source_url/2"
    assert mix_exs =~ "defp source_url(path, line) do"

    assert mix_exs =~
             ~s|"\#{@source_url}/blob/wotex-demo-v\#{@version}/\#{repository_path}#L\#{line}"|

    for link <- ["GitHub", "Changelog", "Specifications"] do
      assert mix_exs =~ ~s|"#{link}" =>|
    end

    for link <- ["Documentation", "Project", "Source"] do
      refute mix_exs =~ ~s|"#{link}" =>|
    end

    refute mix_exs =~ "hex.publish"

    for script <-
          ~w(mix.exs config/config.exs lib/wotex/demo.ex test/wotex/demo_test.exs bin/check_archive.exs
             bin/check_application_free.exs bin/check_boundary.exs) do
      source = File.read!(Path.join([root, "packages/wotex-demo", script]))
      assert {:ok, _} = Code.string_to_quoted(source)
      assert IO.iodata_to_binary([Code.format_string!(source, line_length: 100), "\n"]) == source
    end

    assert File.read!(Path.join(root, "packages/wotex-demo/config/config.exs")) =~
             ~s|version_tag_prefix: "wotex-demo-v"|

    claude = File.read!(Path.join(root, "packages/wotex-demo/CLAUDE.md"))
    assert claude =~ ~r/\A# Wotex Demo package contract\n/
    assert claude =~ "Repository-wide rules are in the root `CLAUDE.md`.\n\n## Invariants\n"
    assert claude =~ "\n## Where things are\n"
    assert claude =~ "\n## Working on this package\n"
    assert claude =~ "`mix pkg wotex-demo test test/wotex/demo_test.exs`"
    assert claude =~ "`mix check.fast --package wotex-demo`"
    assert claude =~ "`mix check` (full gate here"
    assert claude =~ "`mix pkg wotex-demo check --no-retry`"
    assert claude =~ "It uses `wotex` and `wotex-runtime` only through their public"

    readme = File.read!(Path.join(root, "packages/wotex-demo/README.md"))
    assert readme =~ "\n## Installation\n"
    assert readme =~ "\n## Development\n"
    assert readme =~ ~s|{:wotex_demo, "~> 0.1"}|
    refute readme =~ "sparse:"
    refute readme =~ "path: "
    assert readme =~ "mix check.fast --package wotex-demo"
    refute readme =~ "@@"

    assert {:ok, catalogue} =
             YamlElixir.read_from_file(
               Path.join(root, "docs/packages/wotex-demo/specs/catalogue.yaml")
             )

    assert catalogue["package"] == "wotex_demo"
    assert catalogue["specifications"] == []
    # Catalogue paths follow docs/README.md: docs/... is the documentation tree.
    assert catalogue["completion_plan"] == "docs/plans/wotex-demo-completion.md"

    assert File.regular?(
             Path.join(root, Catalogue.resolve_path("wotex-demo", catalogue["completion_plan"]))
           )
  end

  test "omits the sibling switch from a package without siblings", %{root: root} do
    assert {:ok, _} = Scaffold.create("wotex-solo", root: root, depends_on: [])
    mix_exs = File.read!(Path.join(root, "packages/wotex-solo/mix.exs"))
    assert {:ok, _} = Code.string_to_quoted(mix_exs)
    refute mix_exs =~ "sibling("
    claude = File.read!(Path.join(root, "packages/wotex-solo/CLAUDE.md"))
    assert claude =~ "It depends on no sibling package."
  end

  test "every package README and a new package state one toolchain policy from the lanes",
       %{root: root} do
    assert {:ok, _} = Scaffold.create("wotex-demo", root: root, depends_on: ["wotex"])

    policy = fn readme, title ->
      flat = Enum.join(String.split(readme), " ")
      pattern = ~r/#{Regex.escape(title)} 0\.1 supports .*?packages\.yaml\)\./
      assert [sentence] = Regex.run(pattern, flat), "#{title} states no toolchain policy"
      String.replace_prefix(sentence, title, "")
    end

    expected = policy.(File.read!(Path.join(root, "packages/wotex-demo/README.md")), "Wotex Demo")

    for {name, version} <- [{"minimum", "1.18.4"}, {"current", "1.20.2"}] do
      assert {:ok, lane} = Manifest.lane(name)
      assert String.starts_with?(lane.elixir, version <> "-otp-")
      assert expected =~ "Elixir #{version} with Erlang/OTP #{lane.otp}"
    end

    readmes = Path.wildcard(Path.join(Workspace.root(), "packages/*/README.md"))
    assert length(readmes) == map_size(Manifest.load!().packages)

    for path <- readmes do
      readme = File.read!(path)
      ["# " <> title | _] = String.split(readme, "\n", parts: 2)
      assert policy.(readme, title) == expected, path
    end
  end

  test "adds the boundary scan to the template gate once" do
    template =
      "[\n  tools: [\n    {:archive, command: \"a\"},\n    {:diff, command: \"d\"}\n  ]\n]\n"

    assert {:ok, gate} = Scaffold.gate(template)
    assert gate =~ ~s|    {:boundary, command: "elixir bin/check_boundary.exs"},\n    {:archive,|
    assert Scaffold.gate(gate) == {:ok, gate}
    assert Scaffold.gate("[tools: []]") == :error
  end

  test "leaves the template package's native tools out of a new gate" do
    {:ok, gate} =
      Scaffold.gate(File.read!(Path.join(Workspace.root(), "packages/wotex-coap/.check.exs")))

    refute gate =~ "native_"
    refute gate =~ "wotex-coap"
    assert {config, []} = Code.eval_string(gate)
    assert Keyword.has_key?(config[:tools], :boundary)
  end

  test "refuses an existing package, a bad name and unknown dependencies", %{root: root} do
    assert {:error, message} = Scaffold.create("wotex", root: root)
    assert message =~ "already in the manifest"

    File.mkdir_p!(Path.join(root, "packages/wotex-taken"))
    assert {:error, "packages/wotex-taken exists"} = Scaffold.create("wotex-taken", root: root)

    File.mkdir_p!(Path.join(root, "docs/packages/wotex-doc"))
    assert {:error, "docs/packages/wotex-doc exists"} = Scaffold.create("wotex-doc", root: root)

    assert {:error, message} = Scaffold.create("Wotex_Bad", root: root)
    assert message =~ "package name must match"

    assert {:error, "unknown dependencies: wotex-nx"} =
             Scaffold.create("wotex-new", root: root, depends_on: ["wotex-nx"])

    refute File.exists?(Path.join(root, "packages/wotex-new"))
    assert File.read!(Path.join(root, "tooling/packages.yaml")) == @manifest
  end

  test "fails cleanly when a template is missing", %{root: root} do
    File.rm!(Path.join(root, "packages/wotex-coap/.check.exs"))

    assert {:error, "template packages/wotex-coap/.check.exs is missing"} =
             Scaffold.create("wotex-x", root: root)

    refute File.exists?(Path.join(root, "packages/wotex-x"))
  end

  test "derives app and namespace names" do
    assert Scaffold.app("wotex-binding-http") == "wotex_binding_http"
    assert Scaffold.namespace("wotex-binding-http") == "Wotex.BindingHttp"
    assert Scaffold.namespace("wotex-demo") == "Wotex.Demo"
    assert Scaffold.namespace("other-thing") == "OtherThing"
    assert Scaffold.title("wotex-binding-http") == "Wotex Binding Http"

    assert Scaffold.manifest_entry("wotex-demo", ["wotex"]) ==
             "  wotex-demo:\n    app: wotex_demo\n    depends_on: [wotex]\n"
  end
end
