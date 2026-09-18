defmodule Wotex.Lab.Check.NativeContainment do
  @moduledoc false

  @prefix "wotex-lab-native-check-"

  @spec run() :: true
  def run do
    cargo = System.find_executable("cargo") || abort("cargo is required for native containment")
    manifest = Path.expand("../priv/conformance/native/Cargo.toml", __DIR__)
    target = allocate_target()

    try do
      {output, status} =
        System.cmd(
          cargo,
          ["test", "--manifest-path", manifest, "--locked", "--features", "test-probes"],
          env: [{"CARGO_TARGET_DIR", target}],
          stderr_to_stdout: true
        )

      IO.binwrite(output)
      status == 0 || raise "native containment tests failed with status #{status}"
    after
      remove_target!(target)
    end
  end

  defp allocate_target do
    base = Path.expand(System.tmp_dir!())
    path = Path.join(base, @prefix <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower))

    case File.mkdir(path) do
      :ok ->
        :ok = File.chmod(path, 0o700)
        path

      {:error, :eexist} ->
        allocate_target()

      {:error, reason} ->
        abort("cannot allocate native containment target: #{:file.format_error(reason)}")
    end
  end

  defp remove_target!(path) do
    base = Path.expand(System.tmp_dir!())
    path = Path.expand(path)
    basename = Path.basename(path)

    with true <- Path.dirname(path) == base,
         true <- String.starts_with?(basename, @prefix),
         {:ok, %File.Stat{type: :directory}} <- File.lstat(path) do
      File.rm_rf!(path)
      :ok
    else
      _ -> raise "refusing to remove an unowned native containment target"
    end
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Lab.Check.NativeContainment.run()
