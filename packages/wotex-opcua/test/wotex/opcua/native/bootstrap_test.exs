defmodule Wotex.OPCUA.Native.BootstrapTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.OPCUA.Native.Bootstrap

  setup do
    dir =
      Path.join(System.tmp_dir!(), "wotex-opcua-bootstrap-#{System.unique_integer([:positive])}")

    File.mkdir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    %{
      dir: dir,
      source: Path.join(dir, "main.c"),
      output: Path.join(dir, "command"),
      compiler: System.find_executable("cc") || flunk("C11 compiler required")
    }
  end

  test "WOP-X02 trusted bootstrap creates a real C executable with an explicit cleanup limitation",
       c do
    File.write!(c.source, "int main(void) { return 0; }\n")

    assert {:ok, %{output: <<>>, descendant_cleanup: :unverified}} =
             Bootstrap.compile(c.compiler, c.source, c.output, c.dir)

    assert File.regular?(c.output)
    assert {"", 0} = System.cmd(c.output, [], env: [{"CFLAGS", nil}])
  end

  test "WOP-X02 compiler errors retain bounded output and never imply descendant cleanup", c do
    File.write!(c.source, "invalid-C-source\n")

    assert {:error, :bootstrap_failed, %{output: output, descendant_cleanup: :unverified}} =
             Bootstrap.compile(c.compiler, c.source, c.output, c.dir)

    assert byte_size(output) in 1..1_048_576
    refute File.exists?(c.output)

    assert {:error, :bootstrap_failed, _} =
             Bootstrap.compile(c.compiler <> ".absent", c.source, c.output, c.dir)
  end

  test "WOP-X02 invalid bootstrap paths cannot invoke the compiler", c do
    for bad <- [nil, "cc", "/bad\0path"] do
      assert {:error, :invalid_bootstrap, _} = Bootstrap.compile(bad, c.source, c.output, c.dir)
    end

    refute File.exists?(c.output)
  end
end
