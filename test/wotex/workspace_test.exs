defmodule Wotex.WorkspaceTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace

  describe "root/0" do
    test "is the absolute directory of the root Mix project" do
      root = Workspace.root()

      assert Path.type(root) == :absolute
      assert root == Path.expand("../..", __DIR__)
      assert File.regular?(Path.join(root, "mix.exs"))
      assert File.regular?(Path.join(root, "tooling/packages.yaml"))
    end
  end

  describe "relative/2" do
    test "makes an absolute path below the root relative to it" do
      assert Workspace.relative("/repo/packages/wotex/lib/wotex.ex", "/repo") ==
               "packages/wotex/lib/wotex.ex"

      assert Workspace.relative("/repo/packages/../lib/x.ex", "/repo") == "lib/x.ex"
      assert Workspace.relative("/repo/./docs", "/repo") == "docs"
    end

    test "the root itself is ." do
      assert Workspace.relative("/repo", "/repo") == "."
      assert Workspace.relative("/repo/", "/repo") == "."
    end

    test "keeps an absolute path outside the root" do
      assert Workspace.relative("/elsewhere/deps/x.ex", "/repo") == "/elsewhere/deps/x.ex"
      # A sibling whose name starts with the root's name is not below it.
      assert Workspace.relative("/repo-other/x.ex", "/repo") == "/repo-other/x.ex"
    end

    test "returns a relative path unchanged" do
      assert Workspace.relative("packages/wotex", "/repo") == "packages/wotex"
      assert Workspace.relative("../outside", "/repo") == "../outside"
      assert Workspace.relative(".", "/repo") == "."
    end

    test "defaults to the repository root" do
      root = Workspace.root()

      assert Workspace.relative(Path.join(root, "packages/wotex-coap")) == "packages/wotex-coap"
      assert Workspace.relative(root) == "."
      assert Workspace.relative("lib/wotex") == "lib/wotex"
    end
  end
end
