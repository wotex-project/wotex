defmodule Wotex.Workspace.NativeToolsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.NativeTools

  defp opts(overrides) do
    env = Map.get(overrides, :env, %{})
    path = Map.get(overrides, :path, %{})
    files = Map.get(overrides, :files, [])
    versions = Map.get(overrides, :versions, %{})

    [
      env: &Map.get(env, &1),
      find: &Map.get(path, &1),
      exists?: &(&1 in files),
      version: fn executable ->
        case Map.fetch(versions, executable) do
          {:ok, output} -> {:ok, output}
          :error -> :error
        end
      end
    ]
  end

  test "parses the version line of clang-format and clang-tidy" do
    assert NativeTools.parse_version("Ubuntu clang-format version 18.1.3 (1ubuntu1)") ==
             {:ok, "18.1.3", 18}

    assert NativeTools.parse_version("Homebrew clang-format version 23.1.1") == {:ok, "23.1.1", 23}

    assert NativeTools.parse_version("Homebrew LLVM version 23.1.1\n  Optimized build.\n") ==
             {:ok, "23.1.1", 23}

    assert NativeTools.parse_version("clang-format version 21") == {:ok, "21", 21}
    assert NativeTools.parse_version("something else") == :error
  end

  test "searches the variable, PATH, versioned names, then LLVM prefixes" do
    options =
      opts(%{
        env: %{"CLANG_FORMAT" => "cf-explicit"},
        path: %{
          "cf-explicit" => "/opt/cf/cf-explicit",
          "clang-format" => "/usr/bin/clang-format",
          "clang-format-23" => "/usr/bin/clang-format-23"
        },
        files: ["/opt/homebrew/opt/llvm/bin/clang-format", "/usr/lib/llvm-22/bin/clang-format"]
      })

    candidates =
      NativeTools.candidates(:clang_format, options[:env], options[:find], options[:exists?])

    assert candidates ==
             [
               "/opt/cf/cf-explicit",
               "/usr/bin/clang-format",
               "/usr/bin/clang-format-23",
               "/opt/homebrew/opt/llvm/bin/clang-format",
               "/usr/lib/llvm-22/bin/clang-format"
             ]
  end

  test "uses the first candidate that meets the minimum version" do
    options =
      opts(%{
        path: %{"clang-format" => "/usr/bin/clang-format"},
        files: ["/usr/lib/llvm-23/bin/clang-format"],
        versions: %{
          "/usr/bin/clang-format" => "Ubuntu clang-format version 18.1.3",
          "/usr/lib/llvm-23/bin/clang-format" => "clang-format version 23.1.0"
        }
      })

    assert {:ok, found} = NativeTools.find(:clang_format, options)

    assert found == %{
             tool: :clang_format,
             path: "/usr/lib/llvm-23/bin/clang-format",
             version: "23.1.0",
             major: 23
           }
  end

  test "fails with the versions it found and an install hint" do
    too_old =
      opts(%{
        path: %{"clang-tidy" => "/usr/bin/clang-tidy"},
        versions: %{"/usr/bin/clang-tidy" => "Ubuntu LLVM version 18.1.3"}
      })

    assert {:error, message} = NativeTools.find(:clang_tidy, too_old)
    assert message =~ "clang-tidy 22 or later not found (found 18.1.3 at /usr/bin/clang-tidy)"
    assert message =~ "brew install llvm"
    assert message =~ "apt install clang-tidy-23"
    assert message =~ "CLANG_TIDY"

    assert {:error, message} = NativeTools.find(:clang_format, opts(%{}))
    assert message =~ "clang-format not found; install LLVM 22 or later"
  end

  test "names and variables" do
    assert NativeTools.minimum_major() == 22
    assert NativeTools.name(:clang_tidy) == "clang-tidy"
    assert NativeTools.variable(:clang_format) == "CLANG_FORMAT"
  end
end
