defmodule Wotex.Workspace.ScaffoldTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace
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

    for file <- [".check.exs", ".credo.exs", ".formatter.exs", "coveralls.json"] do
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
          packages/wotex-demo/mix.exs packages/wotex-demo/.check.exs packages/wotex-demo/.credo.exs
          packages/wotex-demo/.formatter.exs packages/wotex-demo/coveralls.json
          packages/wotex-demo/CLAUDE.md packages/wotex-demo/README.md packages/wotex-demo/CHANGELOG.md
          packages/wotex-demo/LICENSE packages/wotex-demo/NOTICE packages/wotex-demo/lib/wotex/demo.ex
          packages/wotex-demo/test/test_helper.exs packages/wotex-demo/test/wotex_demo_test.exs
          packages/wotex-demo/bin/check_archive.exs packages/wotex-demo/bin/check_application_free.exs
          docs/packages/wotex-demo/specs/catalogue.yaml docs/packages/wotex-demo/plans/wotex-demo-completion.md
          docs/packages/wotex-demo/provenance/.gitkeep tooling/packages.yaml
        ) do
      assert relative in paths, "#{relative} not reported"
      assert File.exists?(Path.join(root, relative)), "#{relative} not created"
    end

    assert File.read!(Path.join(root, "packages/wotex-demo/.check.exs")) ==
             File.read!(Path.join(root, "packages/wotex-coap/.check.exs"))

    assert File.read!(Path.join(root, "packages/wotex-demo/LICENSE")) ==
             File.read!(Path.join(root, "LICENSE"))

    manifest = Manifest.load!(Path.join(root, "tooling/packages.yaml"))
    demo = Manifest.fetch!("wotex-demo", manifest)
    assert demo.app == "wotex_demo"
    assert demo.depends_on == ["wotex", "wotex-runtime"]
    assert Manifest.topological_order(manifest) == ~w(wotex wotex-runtime wotex-demo)

    mix_exs = File.read!(Path.join(root, "packages/wotex-demo/mix.exs"))
    assert {:ok, _ast} = Code.string_to_quoted(mix_exs)
    assert mix_exs =~ "defmodule Wotex.Demo.MixProject"
    assert mix_exs =~ "app: :wotex_demo"
    assert mix_exs =~ ~s|sibling(:wotex, "wotex")|
    assert mix_exs =~ ~s|sibling(:wotex_runtime, "wotex-runtime")|
    assert mix_exs =~ ~s|System.get_env("WOTEX_PATH_DEPS")|
    assert mix_exs =~ ~s|package: "cmd env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build"|
    refute mix_exs =~ "hex.publish"

    for script <-
          ~w(lib/wotex/demo.ex test/wotex_demo_test.exs bin/check_archive.exs bin/check_application_free.exs) do
      assert {:ok, _ast} =
               Code.string_to_quoted(File.read!(Path.join([root, "packages/wotex-demo", script])))
    end

    assert {:ok, catalogue} =
             YamlElixir.read_from_file(
               Path.join(root, "docs/packages/wotex-demo/specs/catalogue.yaml")
             )

    assert catalogue["package"] == "wotex_demo"
    assert catalogue["specifications"] == []
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

    assert Scaffold.manifest_entry("wotex-demo", ["wotex"]) ==
             "  wotex-demo:\n    app: wotex_demo\n    depends_on: [wotex]\n"
  end
end
