defmodule Wotex.OPCUA.Native.BuildFaultTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.OPCUA.Native.{Bootstrap, Build, Toolchain}

  setup do
    root =
      Path.join(System.tmp_dir!(), "wotex-opcua-build-fault-#{System.unique_integer([:positive])}")

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    assert {:ok, tools} = Toolchain.resolve()
    %{root: root, tools: tools}
  end

  test "WOP-X02 old or malformed curl versions fail before source download", c do
    for {version, directory} <- [{"curl 8.3.0 test", "old"}, {"unrecognized", "malformed"}] do
      isolated(c, directory, :curl, version, 0, 0, fn workspace ->
        assert {:error, :unsupported_download_tool} = Build.run(workspace)
        assert File.ls!(Path.join(workspace, "downloads")) == []
        refute File.exists?(Path.join(workspace, "wotex-native-build.json"))
      end)
    end
  end

  test "WOP-X02 failed version probe and compiler bootstrap remain distinct finite errors", c do
    isolated(c, "version-failed", :curl, "curl 8.4.0 test", 7, 7, fn workspace ->
      assert {:error, %{code: :command_failed, step: :curl, exit_status: 7}} = Build.run(workspace)
      refute File.exists?(Path.join(workspace, "wotex-native-build.json"))
    end)

    isolated(c, "bootstrap-failed", :cc, "unused", 7, 7, fn workspace ->
      assert {:error, %{code: :bootstrap_failed, details: %{descendant_cleanup: :unverified}}} =
               Build.run(workspace)

      refute File.exists?(Path.join(workspace, "wotex-native-build.json"))
    end)
  end

  test "WOP-X02 download failure and corrupted source cannot produce extracted source or completion",
       c do
    isolated(c, "download-failed", :curl, "curl 8.4.0 test", 0, 7, fn workspace ->
      assert {:error, %{code: :command_failed, id: :openssl, exit_status: 7, output_sha256: hash}} =
               Build.run(workspace)

      assert hash =~ ~r/\A[0-9a-f]{64}\z/
      assert File.ls!(Path.join(workspace, "sources")) == []
      refute File.exists?(Path.join(workspace, "wotex-native-build.json"))
    end)

    isolated(c, "digest-failed", :curl, "curl 8.4.0 test", 0, 0, fn workspace ->
      assert {:error, :source_digest_mismatch} = Build.run(workspace)
      assert File.ls!(Path.join(workspace, "sources")) == []
      assert File.read!(Path.join(workspace, "downloads/openssl.tar.gz")) == "invalid-source"
      refute File.exists?(Path.join(workspace, "wotex-native-build.json"))
    end)
  end

  defp isolated(c, name, selected, version, version_status, command_status, assertion) do
    root = Path.join(c.root, name)
    tools_dir = Path.join(root, "tools")
    File.mkdir_p!(tools_dir)
    executable = Path.join(root, "fault-tool")
    source = Path.join(root, "fault.c")

    File.write!(source, """
    #include <stdio.h>
    #include <string.h>
    int main(int argc, char **argv) {
      if(argc >= 2 && strcmp(argv[argc - 1], "--version") == 0) {
        puts("#{version}"); return #{version_status};
      }
      for(int i = 1; i + 1 < argc; i++) {
        if(strcmp(argv[i], "--output") == 0) {
          FILE *output = fopen(argv[i + 1], "wb");
          if(!output) return 9;
          fputs("invalid-source", output); fclose(output);
        }
      }
      return #{command_status};
    }
    """)

    assert {:ok, _} = Bootstrap.compile(c.tools.paths.cc, source, executable, root)

    for {key, path} <- c.tools.paths do
      name =
        case key do
          :python -> "python3"
          :system -> if elem(c.tools.target, 0) == :darwin, do: "sw_vers", else: "ldd"
          :linker -> "ld"
          key -> Atom.to_string(key)
        end

      File.ln_s!(if(key == selected, do: executable, else: path), Path.join(tools_dir, name))
    end

    original = System.fetch_env!("PATH")

    try do
      System.put_env("PATH", tools_dir)
      assertion.(Path.join(root, "workspace"))
    after
      System.put_env("PATH", original)
    end
  end
end
