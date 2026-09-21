defmodule Wotex.Matter.NativeExecutableTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter.Error
  alias Wotex.Matter.Native.Executable

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-matter-executable-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory}
  end

  test "WMA-B01 admits exact executable content without starting it", context do
    bytes = :binary.copy(<<0, 1, 255>>, 100_000)
    {path, digest} = executable(context.directory, "host", bytes)

    assert {:ok, admitted} = Executable.verify(path, digest, deadline())
    assert admitted.path == path
    assert admitted.sha256 == digest
    assert admitted.bytes == byte_size(bytes)
    assert admitted.identity.inode == File.stat!(path).inode
    refute inspect(admitted) =~ path
  end

  test "WMA-B01 rejects mismatched, absent, linked and nonexecutable inputs", context do
    {path, digest} = executable(context.directory, "host", "exact bytes")
    link = Path.join(context.directory, "link")
    File.ln_s!(path, link)

    assert {:error, %Error{code: :incompatible_backend, field: :executable}} =
             Executable.verify(path, String.duplicate("0", 64), deadline())

    for rejected <- [link, context.directory, Path.join(context.directory, "missing")] do
      assert {:error, %Error{code: :transport_unavailable, field: :executable}} =
               Executable.verify(rejected, digest, deadline())
    end

    File.chmod!(path, 0o600)

    assert {:error, %Error{code: :transport_unavailable}} =
             Executable.verify(path, digest, deadline())
  end

  test "WMA-B01 rejects empty and oversized executables before hashing", context do
    {empty, digest} = executable(context.directory, "empty", "")

    assert {:error, %Error{code: :transport_unavailable}} =
             Executable.verify(empty, digest, deadline())

    path = Path.join(context.directory, "oversized")
    {:ok, file} = File.open(path, [:write, :binary, :raw])
    {:ok, 536_870_912} = :file.position(file, 536_870_912)
    :ok = :file.write(file, <<0>>)
    :ok = File.close(file)
    File.chmod!(path, 0o700)

    assert {:error, %Error{code: :transport_unavailable}} =
             Executable.verify(path, String.duplicate("0", 64), deadline())
  end

  test "WMA-B01 expires the original budget and rejects malformed selectors" do
    now = System.monotonic_time(:millisecond)

    assert {:error, %Error{code: :timeout, field: :executable}} =
             Executable.verify("/missing", String.duplicate("0", 64), now)

    for {path, digest, limit} <- [
          {"relative", String.duplicate("0", 64), deadline()},
          {"/missing", "bad", deadline()},
          {"/missing", String.duplicate("0", 64), :infinity}
        ] do
      assert {:error, %Error{code: :invalid_options, field: :executable}} =
               Executable.verify(path, digest, limit)
    end
  end

  defp executable(directory, name, bytes) do
    path = Path.join(directory, name)
    File.write!(path, bytes)
    File.chmod!(path, 0o700)
    {path, digest(bytes)}
  end

  defp digest(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp deadline, do: System.monotonic_time(:millisecond) + 5_000
end
