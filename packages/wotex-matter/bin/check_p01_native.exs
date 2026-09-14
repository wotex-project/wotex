defmodule Wotex.Matter.Check.P01Native do
  @moduledoc false

  @image "node:24-bookworm@sha256:6dac556d980b7f0e5498d08f08cee0ca67798b4ad6c23964a9214920e67758d0"

  @script """
  set -eu
  apt-get update -qq
  apt-get install -y -qq cmake ninja-build
  uname -m | grep -Fx x86_64
  g++ -dumpfullversion -dumpversion | grep -Fx 12.2.0
  cmake --version | grep -F 'cmake version 3.25.1'
  ninja --version | grep -Fx 1.11.1
  cmake -S /src/native -B /work/normal -G Ninja -DWOTEX_MATTER_SANITIZERS=OFF
  cmake --build /work/normal
  ctest --test-dir /work/normal --output-on-failure
  cmake -S /src/native -B /work/sanitized -G Ninja -DWOTEX_MATTER_SANITIZERS=ON
  cmake --build /work/sanitized
  ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
    ctest --test-dir /work/sanitized --output-on-failure
  """

  @spec main() :: :ok
  def main do
    source = File.cwd!()
    workspace = Path.join(System.tmp_dir!(), "wotex-matter-p01-native-#{unique()}")
    File.mkdir_p!(workspace)

    arguments = [
      "run",
      "--rm",
      "--platform",
      "linux/amd64",
      "--volume",
      "#{source}:/src:ro",
      "--volume",
      "#{workspace}:/work",
      @image,
      "bash",
      "-lc",
      @script
    ]

    try do
      {_output, status} =
        System.cmd("docker", arguments,
          into: IO.stream(),
          stderr_to_stdout: true
        )

      if status == 0 do
        IO.puts("WMA-P01 native value lane passed")
        :ok
      else
        System.halt(status)
      end
    after
      File.rm_rf!(workspace)
    end
  end

  defp unique, do: System.unique_integer([:positive, :monotonic])
end

Wotex.Matter.Check.P01Native.main()
