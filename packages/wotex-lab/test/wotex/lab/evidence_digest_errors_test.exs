defmodule Wotex.Lab.EvidenceDigestErrorsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Evidence.Digest

  test "unreadable files fail file and tree digests and file! raises" do
    root =
      Path.join(System.tmp_dir!(), "wotex-lab-unreadable-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    locked = Path.join(root, "locked.txt")
    File.write!(locked, "secret")
    File.chmod!(locked, 0o000)

    on_exit(fn ->
      File.chmod(locked, 0o600)
      File.rm_rf!(root)
    end)

    assert {:error, :eacces} = Digest.file(locked)
    assert {:error, :eacces} = Digest.tree(root, ["*.txt"])
    assert_raise File.Error, fn -> Digest.file!(locked) end
    assert Digest.file!(__ENV__.file) == Digest.bytes(File.read!(__ENV__.file))
  end
end
