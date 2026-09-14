defmodule Wotex.Matter.Check.P02Native do
  @moduledoc false

  @image "node:24-bookworm@sha256:6dac556d980b7f0e5498d08f08cee0ca67798b4ad6c23964a9214920e67758d0"
  @sdk_revision "250a9e6c50ee2068107f3c4808b680f5f2925415"
  @sdk_sha256 "83032f0c98b02c8c16defc6e70ebe288c127ef3661153feca32839fb65b33628"
  @nlassert_revision "c5892c5ae43830f939ed660ff8ac5f1b91d336d3"
  @nlassert_sha256 "392f0a7f1c35cc3520d5f71faf37bfe4518e00ba0dc704068f4fbf6eba5427a5"
  @nlio_revision "0e725502c2b17bb0a0c22ddd4bcaee9090c8fb5c"
  @nlio_sha256 "f7ffbc6fd3e9029c6aa558aec8f80819d1e9a8daba67633d512de23560147f34"
  @json_sha256 "9bea4c8066ef4a1c206b2be5a36302f8926f7fdc6087af5d20b417d0cf103ea6"

  @script """
  set -eu
  apt-get update -qq
  apt-get install -y -qq ca-certificates cmake curl ninja-build
  uname -m | grep -Fx x86_64
  g++ -dumpfullversion -dumpversion | grep -Fx 12.2.0
  cmake --version | grep -F 'cmake version 3.25.1'
  ninja --version | grep -Fx 1.11.1
  curl -fsSL "https://codeload.github.com/project-chip/connectedhomeip/tar.gz/#{@sdk_revision}" -o /work/sdk.tar.gz
  printf '#{@sdk_sha256}  /work/sdk.tar.gz\n' | sha256sum -c -
  mkdir -p /work/sdk
  tar -xzf /work/sdk.tar.gz -C /work/sdk --strip-components=1
  curl -fsSL "https://codeload.github.com/nestlabs/nlassert/tar.gz/#{@nlassert_revision}" -o /work/nlassert.tar.gz
  printf '#{@nlassert_sha256}  /work/nlassert.tar.gz\n' | sha256sum -c -
  mkdir -p /work/sdk/third_party/nlassert/repo
  tar -xzf /work/nlassert.tar.gz -C /work/sdk/third_party/nlassert/repo --strip-components=1
  curl -fsSL "https://codeload.github.com/nestlabs/nlio/tar.gz/#{@nlio_revision}" -o /work/nlio.tar.gz
  printf '#{@nlio_sha256}  /work/nlio.tar.gz\n' | sha256sum -c -
  mkdir -p /work/sdk/third_party/nlio/repo
  tar -xzf /work/nlio.tar.gz -C /work/sdk/third_party/nlio/repo --strip-components=1
  mkdir -p /work/json/nlohmann
  curl -fsSL 'https://raw.githubusercontent.com/nlohmann/json/v3.11.3/single_include/nlohmann/json.hpp' -o /work/json/nlohmann/json.hpp
  printf '#{@json_sha256}  /work/json/nlohmann/json.hpp\n' | sha256sum -c -
  cmake -S /src/native -B /work/normal -G Ninja \
    -DWOTEX_MATTER_SANITIZERS=OFF \
    -DWOTEX_MATTER_SDK_ROOT=/work/sdk \
    -DWOTEX_MATTER_JSON_INCLUDE=/work/json
  cmake --build /work/normal
  ctest --test-dir /work/normal --output-on-failure
  cmake -S /src/native -B /work/sanitized -G Ninja \
    -DWOTEX_MATTER_SANITIZERS=ON \
    -DWOTEX_MATTER_SDK_ROOT=/work/sdk \
    -DWOTEX_MATTER_JSON_INCLUDE=/work/json
  cmake --build /work/sanitized
  ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
    ctest --test-dir /work/sanitized --output-on-failure
  """

  @spec main() :: :ok
  def main do
    source = File.cwd!()
    workspace = Path.join(System.tmp_dir!(), "wotex-matter-p02-native-#{unique()}")
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
        IO.puts("WMA-P02 durable storage lane passed")
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

Wotex.Matter.Check.P02Native.main()
