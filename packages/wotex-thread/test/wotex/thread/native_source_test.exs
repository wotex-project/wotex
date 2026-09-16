defmodule Wotex.Thread.NativeSourceTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Thread.Native.Source

  setup do
    root = Path.join(System.tmp_dir!(), "wotex-thread-source-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "WTH-B01 exact Spinel and discerner patches reject mismatched bytes", %{root: root} do
    spinel = Path.join(root, "src/lib/spinel/spinel.c")
    discerner = Path.join(root, "src/core/meshcop/meshcop.hpp")
    File.mkdir_p!(Path.dirname(spinel))
    File.mkdir_p!(Path.dirname(discerner))
    before_spinel = "(data_in[3] << 24); (data_in[3] << 24); (data_in[7] << 24)"

    after_spinel =
      "((uint32_t)data_in[3] << 24); ((uint32_t)data_in[3] << 24); ((uint32_t)data_in[7] << 24)"

    before_discerner = "return (static_cast<uint64_t>(1ULL) << mLength) - 1;"

    after_discerner =
      "return mLength == 64 ? ~static_cast<uint64_t>(0) : (static_cast<uint64_t>(1ULL) << mLength) - 1;"

    File.write!(spinel, before_spinel)
    File.write!(discerner, before_discerner)

    spinel_pin = pin("src/lib/spinel/spinel.c", before_spinel, after_spinel)
    discerner_pin = pin("src/core/meshcop/meshcop.hpp", before_discerner, after_discerner)

    assert {:error, :unexpected_sdk_source} =
             Source.patch_spinel(root, %{spinel_pin | "after_sha256" => String.duplicate("0", 64)})

    assert File.read!(spinel) == before_spinel
    assert :ok = Source.patch_spinel(root, spinel_pin)
    assert File.read!(spinel) == after_spinel
    assert {:error, :unexpected_sdk_source} = Source.patch_spinel(root, spinel_pin)
    assert :ok = Source.patch_discerner(root, discerner_pin)
    assert File.read!(discerner) == after_discerner
    assert {:error, :unexpected_sdk_source} = Source.patch_discerner(root, discerner_pin)
    File.write!(spinel, "unknown")
    assert {:error, :unexpected_sdk_source} = Source.patch_spinel(root, spinel_pin)
  end

  test "WTH-B01 archive admits finite regular files and rejects links", %{root: root} do
    tree = Path.join(root, "tree")
    File.mkdir_p!(Path.join(tree, "root"))
    File.write!(Path.join(tree, "root/run"), "data")
    File.chmod!(Path.join(tree, "root/run"), 0o755)
    archive = Path.join(root, "safe.tar.gz")
    assert {_, 0} = tar(["czf", archive, "-C", tree, "root"])
    assert {:ok, _} = Source.validate_archive(archive, "root")
    destination = Path.join(root, "output")
    assert :ok = Source.extract(archive, destination, "root")
    assert File.read!(Path.join(destination, "root/run")) == "data"
    assert {:error, :invalid_source_archive} = Source.extract(archive, destination, "root")
    assert {:error, :invalid_source_archive} = Source.validate_archive(archive, "other")

    File.ln_s!("run", Path.join(tree, "root/link"))
    assert {:error, :invalid_source_file} = Source.digest(Path.join(tree, "root/link"))
    linked = Path.join(root, "linked.tar.gz")
    assert {_, 0} = tar(["czf", linked, "-C", tree, "root"])
    assert {:error, :invalid_source_archive} = Source.validate_archive(linked, "root")
    refute File.exists?(Path.join(root, "linked-output"))
    File.ln_s!(destination, Path.join(root, "output-link"))

    assert {:error, :invalid_source_archive} =
             Source.extract(archive, Path.join(root, "output-link"), "root")
  end

  defp pin(source, before, expected) do
    %{
      "source" => source,
      "before_sha256" => hash(before),
      "after_sha256" => hash(expected)
    }
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp tar(args) do
    System.cmd("tar", args, env: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end))
  end
end
