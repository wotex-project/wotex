Code.require_file("../../../bin/support/work_directory.exs", __DIR__)

defmodule Wotex.Lab.CheckWorkDirectoryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Check.WorkDirectory

  test "checks exclusively create private attempts and never merge or remove old content" do
    root =
      Path.join(
        System.tmp_dir!(),
        "wotex-check-dir-" <> Base.encode16(:crypto.strong_rand_bytes(16))
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    old = Path.join(root, ".archive-check.138")
    File.mkdir!(old)
    File.write!(Path.join(old, "retention-sentinel"), "previous attempt")

    paths =
      for kind <- [:package, :archive_consumer, :workbench_archive, :reference], _ <- 1..12 do
        path = WorkDirectory.create!(root, kind)
        assert Path.dirname(path) == root
        assert Regex.match?(~r/[a-f0-9]{32}\z/, Path.basename(path))
        assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o700
        assert File.ls!(path) == []
        File.write!(Path.join(path, "retention-sentinel"), "new attempt")
        path
      end

    assert length(Enum.uniq(paths)) == 48
    assert File.read!(Path.join(old, "retention-sentinel")) == "previous attempt"
    assert Enum.all?(paths, &(File.read!(Path.join(&1, "retention-sentinel")) == "new attempt"))
    assert_raise KeyError, fn -> WorkDirectory.create!(root, :unknown) end
    assert length(File.ls!(root)) == 49
  end
end
