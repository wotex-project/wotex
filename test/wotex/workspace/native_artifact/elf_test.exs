defmodule Wotex.Workspace.NativeArtifact.ELFTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.NativeArtifact.ELF
  alias WotexWorkspace.Fixtures
  alias WotexWorkspace.NativeArtifactELFFixture, as: Fixture

  setup context do
    %{root: Fixtures.tmp_dir(context)}
  end

  test "reads target identity, interpreter and dynamic names without host tools", context do
    path =
      Fixture.write!(Path.join(context.root, "tool"),
        interpreter: "/lib64/ld-linux-x86-64.so.2",
        needed: ["libc.so.6", "libpthread.so.0"],
        soname: "tool.so"
      )

    assert ELF.file?(path)
    assert {:ok, elf} = ELF.inspect(path)
    assert elf.class == "elf64"
    assert elf.architecture == "x86_64"
    assert elf.endianness == "little"
    assert elf.type == "executable"
    assert elf.interpreter == "/lib64/ld-linux-x86-64.so.2"
    assert elf.needed == ["libc.so.6", "libpthread.so.0"]
    assert elf.soname == "tool.so"
    assert elf.sha256 =~ ~r/^[0-9a-f]{64}$/
  end

  test "supports explicit 32-bit and big-endian layouts", context do
    path =
      Fixture.write!(Path.join(context.root, "arm.so"),
        class: "elf32",
        endianness: "big",
        architecture: "arm",
        needed: ["libbase.so"],
        soname: "libarm.so"
      )

    assert {:ok, elf} = ELF.inspect(path)
    assert elf.class == "elf32"
    assert elf.architecture == "arm"
    assert elf.endianness == "big"
    assert elf.needed == ["libbase.so"]
  end

  test "accepts an ELF32 object with only its 52-byte header", context do
    bytes = Fixture.bytes(class: "elf32")
    <<before_count::binary-size(44), _::binary-size(2), rest::binary>> = bytes
    header = binary_part(before_count <> <<0, 0>> <> rest, 0, 52)
    path = Fixtures.write!(context.root, "header-only-32", header)

    assert {:ok, elf} = ELF.inspect(path)
    assert elf.class == "elf32"
    assert elf.architecture == "x86_64"
    assert elf.needed == []
  end

  test "rejects malformed headers, tables, names and resource bounds", context do
    plain = Fixtures.write!(context.root, "plain", "not elf")
    refute ELF.file?(plain)
    assert {:error, message} = ELF.inspect(plain)
    assert message =~ "outside the file"

    path = Fixture.write!(Path.join(context.root, "tool"), needed: ["libc.so.6"])
    bytes = File.read!(path)
    <<prefix::binary-size(56), _::binary-size(2), suffix::binary>> = bytes
    File.write!(path, prefix <> <<0xFF, 0xFF>> <> suffix)
    assert {:error, message} = ELF.inspect(path)
    assert message =~ "extended program-header counts"

    bad_name = Fixture.write!(Path.join(context.root, "bad-name"), needed: ["../libc.so.6"])
    assert {:error, message} = ELF.inspect(bad_name)
    assert message =~ "plain UTF-8 library name"

    bounded = Fixture.write!(Path.join(context.root, "bounded"))
    assert {:error, message} = ELF.inspect(bounded, max_bytes: 1)
    assert message =~ "exceeds 1 bytes"
  end

  test "rejects symlinks and non-absolute inputs", context do
    path = Fixture.write!(Path.join(context.root, "tool"))
    link = Path.join(context.root, "link")
    File.ln_s!(path, link)

    refute ELF.file?(link)
    assert {:error, message} = ELF.inspect(link)
    assert message =~ "symlink"
    assert {:error, "ELF path must be absolute"} = ELF.inspect("relative")
  end
end
