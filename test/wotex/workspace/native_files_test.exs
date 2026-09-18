defmodule Wotex.Workspace.NativeFilesTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.NativeFiles
  alias WotexWorkspace.Fixtures

  @ignore """
  # vendored
  packages/coap/native/oscore/vendor/**

    packages/matter/test/support/software/*.inc
  /packages/ble/priv/native/vendor/json.hpp
  """

  @paths ~w(
    packages/coap/native/oscore/worker.c
    packages/coap/native/oscore/worker.h
    packages/coap/native/oscore/vendor/yyjson/yyjson.c
    packages/coap/native/oscore/vendor/yyjson/yyjson.h
    packages/coap/native/oscore/README.md
    packages/matter/native/src/value.cpp
    packages/matter/native/include/wotex_matter/value.hpp
    packages/matter/test/support/software/bridge_control.inc
    packages/ble/priv/native/vendor/json.hpp
    packages/ble/priv/native/main.cpp
    packages/lab/priv/conformance/native/Cargo.toml
    packages/lab/priv/conformance/native/src/main.rs
    packages/coap/native/oscore/vendor/crate/Cargo.toml
  )

  test "parses .clang-format-ignore, skipping comments and blank lines" do
    assert NativeFiles.parse_ignore(@ignore) ==
             {:ok,
              [
                "packages/coap/native/oscore/vendor/**",
                "packages/matter/test/support/software/*.inc",
                "packages/ble/priv/native/vendor/json.hpp"
              ]}

    assert {:error, message} = NativeFiles.parse_ignore("!packages/keep.c\n")
    assert message =~ "negated patterns are not supported"
  end

  test "selects first-party C and C++ files and excludes vendored and pinned ones" do
    {:ok, patterns} = NativeFiles.parse_ignore(@ignore)

    assert NativeFiles.select(@paths, patterns) == [
             "packages/ble/priv/native/main.cpp",
             "packages/coap/native/oscore/worker.c",
             "packages/coap/native/oscore/worker.h",
             "packages/matter/native/include/wotex_matter/value.hpp",
             "packages/matter/native/src/value.cpp"
           ]

    assert NativeFiles.crates(@paths, patterns) == [
             "packages/lab/priv/conformance/native/Cargo.toml"
           ]

    assert NativeFiles.ignored?("packages/coap/native/oscore/vendor", patterns)
    refute NativeFiles.ignored?("packages/coap/native/oscore/vendored.c", patterns)
  end

  test "classifies languages and translation units" do
    assert NativeFiles.language("a/b.c") == :c
    assert NativeFiles.language("a/b.h") == :c
    assert NativeFiles.language("a/b.hpp") == :cpp
    assert NativeFiles.language("a/b.cc") == :cpp
    assert NativeFiles.translation_unit?("a/b.cpp")
    assert NativeFiles.translation_unit?("a/b.c")
    refute NativeFiles.translation_unit?("a/b.h")
    refute NativeFiles.translation_unit?("a/b.hpp")
    refute NativeFiles.c_family?("a/b.inc")
    refute NativeFiles.c_family?("a/b.rs")
  end

  test "lists tracked and untracked, not ignored, files of a package", context do
    root = Fixtures.tmp_dir(context)
    git!(root, ["init", "--quiet"])
    Fixtures.write!(root, ".gitignore", "build/\n")
    Fixtures.write!(root, ".clang-format-ignore", "packages/p/vendor/**\n")
    Fixtures.write!(root, "packages/p/src/a.c", "int a;\n")
    Fixtures.write!(root, "packages/p/vendor/v.c", "int v;\n")
    Fixtures.write!(root, "packages/p/Cargo.toml", "[package]\n")
    Fixtures.write!(root, "packages/q/src/q.c", "int q;\n")
    git!(root, ["add", "."])
    git!(root, ["-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-qm", "init"])
    Fixtures.write!(root, "packages/p/src/new.hpp", "int n;\n")
    Fixtures.write!(root, "packages/p/build/generated.c", "int g;\n")
    File.rm!(Path.join(root, "packages/p/src/a.c"))
    Fixtures.write!(root, "packages/p/src/b.cpp", "int b;\n")

    assert {:ok, found} = NativeFiles.package("packages/p", root)
    assert found.sources == ["packages/p/src/b.cpp", "packages/p/src/new.hpp"]
    assert found.crates == ["packages/p/Cargo.toml"]
    refute "packages/p/build/generated.c" in found.files
    assert "packages/p/vendor/v.c" in found.files
  end

  defp git!(root, args) do
    {_, 0} =
      System.cmd("git", args, cd: root, env: [{"GIT_CONFIG_NOSYSTEM", "1"}], stderr_to_stdout: true)
  end
end
