defmodule Wotex.Lab.Test.NativeContainment do
  @moduledoc false

  alias Wotex.Lab.Evidence.Digest

  @doc false
  def build! do
    root = Path.expand("../..", __DIR__)
    manifest = Path.join(root, "priv/conformance/native/Cargo.toml")
    target = Path.join(root, "_build/containment")
    common = ["--locked", "--manifest-path", manifest, "--target-dir", target]

    commands = [
      ["fmt", "--manifest-path", manifest, "--", "--check"],
      ["test", "--features", "test-probes" | common],
      ["clippy", "--features", "test-probes", "--all-targets" | common] ++ ["--", "-D", "warnings"],
      ["build", "--release", "--features", "test-probes" | common]
    ]

    Enum.each(commands, fn args ->
      case System.cmd("cargo", args, cd: root, stderr_to_stdout: true) do
        {_output, 0} -> :ok
        {output, _status} -> raise "native containment build/test failed:\n#{output}"
      end
    end)

    executable = Path.join(target, "release/wotex-contained-exec")
    {:ok, digest} = Digest.file(executable)

    %{
      launcher: %{executable: executable, digest: digest},
      probe: Path.join(target, "release/containment-probe")
    }
  end
end
