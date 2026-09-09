defmodule Wotex.OPCUA.Native.ExecutableTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.OPCUA.{Error, Native.Executable}

  setup do
    directory =
      Path.join(System.tmp_dir!(), "wotex-native-executable-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory}
  end

  test "WOP-X01 exact streamed executable content is admitted without executing it", context do
    file = Path.join(context.directory, "explicit-program")
    bytes = :binary.copy(<<0, 1, 255>>, 100_000)
    File.write!(file, bytes)
    File.chmod!(file, 0o700)
    expected = digest(bytes)
    assert {:ok, result} = Executable.verify(file, expected, deadline())
    assert result.path == file
    assert result.bytes == byte_size(bytes)
    assert result.sha256 == expected
    assert result.identity.inode == File.stat!(file).inode
    refute inspect(result) =~ file
  end

  test "WOP-X01 content mismatch, symlink, absent, directory and nonexecutable files fail",
       context do
    file = Path.join(context.directory, "program")
    File.write!(file, "bytes")

    assert {:error, %Error{code: :invalid_native_executable}} =
             Executable.verify(file, digest("bytes"), deadline())

    File.chmod!(file, 0o700)
    link = file <> ".link"
    File.ln_s!(file, link)

    for {path, hash} <- [
          {file, digest("different")},
          {link, digest("bytes")},
          {file <> ".absent", digest("bytes")},
          {context.directory, digest("bytes")}
        ] do
      assert {:error, %Error{code: :invalid_native_executable, details: %{}}} =
               Executable.verify(path, hash, deadline())
    end
  end

  test "WOP-X01 empty and oversized sparse files are rejected before hashing", context do
    path = Path.join(context.directory, "oversized")
    File.write!(path, "")
    File.chmod!(path, 0o700)

    assert {:error, %Error{code: :invalid_native_executable}} =
             Executable.verify(path, digest(""), deadline())

    {:ok, file} = File.open(path, [:read, :write, :binary, :raw])
    assert {:ok, 536_870_912} = :file.position(file, 536_870_912)
    assert :ok = :file.write(file, "x")
    File.close(file)

    assert {:error, %Error{code: :invalid_native_executable}} =
             Executable.verify(path, digest(""), deadline())
  end

  test "WOP-X01 expired budget wins before filesystem access", context do
    assert {:error, %Error{code: :deadline_exceeded, field: :executable}} =
             Executable.verify(
               Path.join(context.directory, "absent"),
               digest(""),
               System.monotonic_time(:millisecond)
             )
  end

  test "WOP-X01 malformed executable values are structured errors" do
    for {path, hash, time} <- [
          {nil, digest("x"), deadline()},
          {"relative", digest("x"), deadline()},
          {"/x", nil, deadline()},
          {"/x", "00", deadline()},
          {"/x", String.duplicate("0", 10_000), deadline()},
          {"/x", digest("x"), :infinity},
          {"/x", digest("x"), 9_223_372_036_854_775_808}
        ] do
      assert {:error, %Error{code: :invalid_native_executable}} =
               Executable.verify(path, hash, time)
    end
  end

  defp deadline, do: System.monotonic_time(:millisecond) + 5000
  defp digest(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
