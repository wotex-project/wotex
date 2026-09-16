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

  test "WTH-B01 cached downloads require a pinned HTTPS URL and exact digest", %{root: root} do
    target = Path.join(root, "source.tar.gz")

    url =
      "https://codeload.github.com/Mbed-TLS/mbedtls-framework/tar.gz/dde0c4a0e448a0552f18817dcea633bb851fd288"

    File.write!(target, "cached archive")
    assert :ok = Source.fetch(url, target, hash("cached archive"))

    assert {:error, :invalid_source_download} =
             Source.fetch("http://example.com/a", target, hash("cached archive"))

    assert {:error, :invalid_source_download} =
             Source.fetch(url, "relative", hash("cached archive"))

    assert {:error, :invalid_source_download} = Source.fetch(url, target, "wrong hash")
    assert {:error, :source_hash_mismatch} = Source.fetch(url, target, hash("other"))
    assert File.read!(target) == "cached archive"

    linked = Path.join(root, "linked.tar.gz")
    File.ln_s!(target, linked)
    assert {:error, :invalid_source_download} = Source.fetch(url, linked, hash("cached archive"))
  end

  test "WTH-B01 source-tree hash and SDK merge preserve bytes and executable mode", %{root: root} do
    source = Path.join(root, "framework")
    destination = Path.join(root, "mbedtls/framework")
    File.mkdir_p!(Path.join(source, "scripts"))
    File.mkdir_p!(destination)
    File.write!(Path.join(source, "scripts/generate"), "run")
    File.chmod!(Path.join(source, "scripts/generate"), 0o755)
    File.write!(Path.join(destination, "keep"), "existing")
    assert {:ok, original} = Source.tree_digest(source)
    assert :ok = Source.copy_tree(source, destination)
    assert File.read!(Path.join(destination, "keep")) == "existing"
    assert File.read!(Path.join(destination, "scripts/generate")) == "run"
    assert Bitwise.band(File.stat!(Path.join(destination, "scripts/generate")).mode, 0o777) == 0o755

    File.write!(Path.join(source, "scripts/generate"), "changed")
    assert {:ok, changed} = Source.tree_digest(source)
    refute changed == original
    File.ln_s!("generate", Path.join(source, "scripts/link"))
    assert {:error, :invalid_source_tree} = Source.tree_digest(source)
    assert {:error, :invalid_source_tree} = Source.copy_tree(source, destination)
  end

  test "WTH-B01 archive rejects traversal, absolute names and unsupported entry types", %{
    root: root
  } do
    for {name, type} <- [
          {"../escape", "0"},
          {"/absolute", "0"},
          {"root/../escape", "0"},
          {"different/file", "0"},
          {"root/link", "1"},
          {"root/link", "2"},
          {"root/device", "3"},
          {"root/fifo", "6"}
        ] do
      archive = Path.join(root, "crafted-#{System.unique_integer([:positive])}.tar.gz")
      File.write!(archive, crafted_archive(name, type))
      assert {:error, :invalid_source_archive} = Source.validate_archive(archive, "root")
      destination = Path.join(root, "destination")
      assert {:error, :invalid_source_archive} = Source.extract(archive, destination, "root")
      refute File.exists?(destination)
    end
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

  defp crafted_archive(name, type) do
    size = if type == "0", do: 4, else: 0

    header =
      field(name, 100) <>
        octal(0o7777, 8) <>
        octal(0, 8) <>
        octal(0, 8) <>
        octal(size, 12) <>
        octal(0, 12) <>
        String.duplicate(" ", 8) <>
        type <>
        field("/outside", 100) <>
        "ustar" <>
        <<0>> <>
        "00" <>
        field("", 32) <>
        field("", 32) <> octal(0, 8) <> octal(0, 8) <> field("", 155) <> field("", 12)

    checksum =
      header
      |> :binary.bin_to_list()
      |> Enum.sum()

    check = String.pad_leading(Integer.to_string(checksum, 8), 6, "0") <> <<0, 32>>
    header = binary_part(header, 0, 148) <> check <> binary_part(header, 156, 356)
    data = if size == 4, do: "data" <> :binary.copy(<<0>>, 508), else: ""
    :zlib.gzip(header <> data <> :binary.copy(<<0>>, 1024))
  end

  defp field(value, width), do: value <> :binary.copy(<<0>>, width - byte_size(value))

  defp octal(value, width),
    do: String.pad_leading(Integer.to_string(value, 8), width - 1, "0") <> <<0>>
end
