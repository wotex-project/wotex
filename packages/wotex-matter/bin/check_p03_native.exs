defmodule Wotex.Matter.Check.P03Native do
  @moduledoc false

  import Bitwise

  @image "node:24-bookworm@sha256:6dac556d980b7f0e5498d08f08cee0ca67798b4ad6c23964a9214920e67758d0"
  @sdk_revision "250a9e6c50ee2068107f3c4808b680f5f2925415"
  @sdk_sha256 "83032f0c98b02c8c16defc6e70ebe288c127ef3661153feca32839fb65b33628"
  @pigweed_revision "c9687b52fa704606d19952255c78142fdb2a131a"
  @pigweed_sha256 "2e8d3380080d2ae9cc56f69d05d6f008989b092d6c9f71dc0c0fa25d4a2c3651"
  @boringssl_revision "9cac8a6b38c1cbd45c77aee108411d588da006fe"
  @boringssl_sha256 "4d0310f2d8dc2bb19598ecc46907d44a93cc3bfbde97943c0e9e34ef4f0698b8"
  @nlassert_revision "c5892c5ae43830f939ed660ff8ac5f1b91d336d3"
  @nlassert_sha256 "392f0a7f1c35cc3520d5f71faf37bfe4518e00ba0dc704068f4fbf6eba5427a5"
  @nlio_revision "0e725502c2b17bb0a0c22ddd4bcaee9090c8fb5c"
  @nlio_sha256 "f7ffbc6fd3e9029c6aa558aec8f80819d1e9a8daba67633d512de23560147f34"
  @uriparser_revision "9b2bed92f5deecf740819f9bf27724bee2fe9c12"
  @uriparser_sha256 "879a0c62cd34216ad1076f3f1a6b4877078ac6cb55b5b38204eb94128a1eea2a"
  @json_revision "9cca280a4d0ccf0c08f47a99aa71d1b0e52f8d03"
  @json_sha256 "9bea4c8066ef4a1c206b2be5a36302f8926f7fdc6087af5d20b417d0cf103ea6"
  @cipd_revision "f78815586bf74e9878223463db7cf315c16853d1"
  @cipd_instance "wzIb8E5mCOKbiJf7unggzWIKqjtBb0z_Fo1m4r0AEk8C"
  @cipd_sha256 "6bf4733d673bfa644d7c1862b62bdc941e1c8f5b6ea886c61c37433f4a53dbb2"
  @gn_instance "NE_8G-C-1QSR3Fzth11KzRynkGGK71LSQjiCBQaD6hoC"
  @gn_sha256 "3dcfa89818814fed6e252a82ef6fc4027184010d05619d224ca4dfc17e8ae85c"
  @zap_version "v2026.05.12-nightly.2"
  @zap_instance "YSTXcN2b2sI35obRtz_f4SiOmbkL8_JFLCk-0fJQwKYC"
  @zap_cli_sha256 "ad4b3bc455eb315c2f9149e8be423255b0acdd4b9cf4acb3beb37c09f126cc9d"
  @python_packages [
    {"click", "8.3.3",
     "https://files.pythonhosted.org/packages/ae/44/c1221527f6a71a01ec6fbad7fa78f1d50dfa02217385cf0fa3eec7087d59/click-8.3.3-py3-none-any.whl",
     "a2bf429bb3033c89fa4936ffb35d5cb471e3719e1f3c8a7c3fff0b8314305613"},
    {"coloredlogs", "15.0.1",
     "https://files.pythonhosted.org/packages/a7/06/3d6badcf13db419e25b07041d9c7b4a2c331d3f4e7134445ec5df57714cd/coloredlogs-15.0.1-py2.py3-none-any.whl",
     "612ee75c546f53e92e70049c9dbfcc18c935a2b9a53b66085ce9ef6a6e5c0934"},
    {"humanfriendly", "10.0",
     "https://files.pythonhosted.org/packages/f0/0f/310fb31e39e2d734ccaa2c0fb981ee41f7bd5056ce9bc29b2248bd569169/humanfriendly-10.0-py2.py3-none-any.whl",
     "1697e1a8a8f550fd43c2865cd84542fc175a61dcb779b6fee18cf6b6ccba1477"},
    {"lark", "1.1.5",
     "https://files.pythonhosted.org/packages/ac/c7/25e678cb94ac2b7be741272d5b2ae099e32e23f36d820e6feb8931b12382/lark-1.1.5-py3-none-any.whl",
     "8476f9903e93fbde4f6c327f74d79e9b4bd0ed9294c5dfa3164ab8c581b5de2a"},
    {"Jinja2", "3.1.6",
     "https://files.pythonhosted.org/packages/62/a1/3d680cbfd5f4b8f15abc1d571870c5fc3e594bb582bc3b64ea099db13e56/jinja2-3.1.6-py3-none-any.whl",
     "85ece4451f492d0c13c5dd7c13a64681a86afae63a5f347908daf103ce6d2f67"},
    {"MarkupSafe", "2.1.2",
     "https://files.pythonhosted.org/packages/5a/94/d056bf5dbadf7f4b193ee2a132b3d49ffa1602371e3847518b2982045425/MarkupSafe-2.1.2-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
     "f2bfb563d0211ce16b63c7cb9395d2c682a23187f54c3d79bfec33e6705473c6"},
    {"lxml", "6.1.0",
     "https://files.pythonhosted.org/packages/a7/23/851cfa33b6b38adb628e45ad51fb27105fa34b2b3ba9d1d4aa7a9428dfe0/lxml-6.1.0-cp311-cp311-manylinux2014_x86_64.manylinux_2_17_x86_64.whl",
     "d036ee7b99d5148072ac7c9b847193decdfeac633db350363f7bce4fff108f0e"},
    {"python-path", "0.1.3",
     "https://files.pythonhosted.org/packages/14/95/88242c8d41bd18e825f8b76f38746d52b25746509e73d3909d9e19947dc1/python_path-0.1.3.tar.gz",
     "b62d9aac1da4daee3f036ed088532cf8b68666d3aa103567dc22b6539316c8b3"}
  ]
  @generation "0123456789abcdef0123456789abcdef"
  @paa "/work/sdk/credentials/development/paa-root-certs"

  @python_downloads Enum.map_join(@python_packages, "\n", fn {_name, _version, url, sha256} ->
                      filename = Path.basename(URI.parse(url).path)

                      "curl -fsSL '#{url}' -o '/work/downloads/#{filename}'\n" <>
                        "printf '#{sha256}  /work/downloads/#{filename}\\n' | sha256sum -c -"
                    end)

  @python_install_paths Enum.map_join(@python_packages, " ", fn {_name, _version, url, _sha256} ->
                          "'/work/downloads/#{Path.basename(URI.parse(url).path)}'"
                        end)

  @build_script """
  set -eu
  trap 'printf "native build failed at line %s\n" "$LINENO" >&2' ERR
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq binutils build-essential ca-certificates cmake curl git \
    libglib2.0-dev ninja-build pkg-config python3 python3-pip
  test -d /work
  cd /work
  mkdir -p downloads sdk tools/gn tools/zap bin metadata
  uname -m | grep -Fx x86_64
  g++ -dumpfullversion -dumpversion | grep -Fx 12.2.0
  cmake --version | grep -F 'cmake version 3.25.1'
  ninja --version | grep -Fx 1.11.1

  #{@python_downloads}
  python3 -m pip install --break-system-packages --no-build-isolation \
    --no-deps --no-index \
    #{@python_install_paths}

  curl -fsSL "https://codeload.github.com/project-chip/connectedhomeip/tar.gz/#{@sdk_revision}" \
    -o /work/downloads/sdk.tar.gz
  printf '#{@sdk_sha256}  /work/downloads/sdk.tar.gz\n' | sha256sum -c -
  tar -xzf /work/downloads/sdk.tar.gz -C /work/sdk --strip-components=1

  curl -fsSL "https://codeload.github.com/google/pigweed/tar.gz/#{@pigweed_revision}" \
    -o /work/downloads/pigweed.tar.gz
  printf '#{@pigweed_sha256}  /work/downloads/pigweed.tar.gz\n' | sha256sum -c -
  mkdir -p /work/sdk/third_party/pigweed/repo
  tar -xzf /work/downloads/pigweed.tar.gz \
    -C /work/sdk/third_party/pigweed/repo --strip-components=1
  printf '%s\n' '# Archive-only system-toolchain build.' \
    > /work/sdk/build_overrides/pigweed_environment.gni

  curl -fsSL "https://codeload.github.com/google/boringssl/tar.gz/#{@boringssl_revision}" \
    -o /work/downloads/boringssl.tar.gz
  printf '#{@boringssl_sha256}  /work/downloads/boringssl.tar.gz\n' | sha256sum -c -
  mkdir -p /work/sdk/third_party/boringssl/repo/src
  tar -xzf /work/downloads/boringssl.tar.gz \
    -C /work/sdk/third_party/boringssl/repo/src --strip-components=1

  curl -fsSL "https://codeload.github.com/nestlabs/nlassert/tar.gz/#{@nlassert_revision}" \
    -o /work/downloads/nlassert.tar.gz
  printf '#{@nlassert_sha256}  /work/downloads/nlassert.tar.gz\n' | sha256sum -c -
  mkdir -p /work/sdk/third_party/nlassert/repo
  tar -xzf /work/downloads/nlassert.tar.gz \
    -C /work/sdk/third_party/nlassert/repo --strip-components=1

  curl -fsSL "https://codeload.github.com/nestlabs/nlio/tar.gz/#{@nlio_revision}" \
    -o /work/downloads/nlio.tar.gz
  printf '#{@nlio_sha256}  /work/downloads/nlio.tar.gz\n' | sha256sum -c -
  mkdir -p /work/sdk/third_party/nlio/repo
  tar -xzf /work/downloads/nlio.tar.gz \
    -C /work/sdk/third_party/nlio/repo --strip-components=1

  curl -fsSL "https://codeload.github.com/uriparser/uriparser/tar.gz/#{@uriparser_revision}" \
    -o /work/downloads/uriparser.tar.gz
  printf '#{@uriparser_sha256}  /work/downloads/uriparser.tar.gz\n' | sha256sum -c -
  mkdir -p /work/sdk/third_party/uriparser/repo
  tar -xzf /work/downloads/uriparser.tar.gz \
    -C /work/sdk/third_party/uriparser/repo --strip-components=1

  cp -R /src/native /work/sdk/examples/wotex-matter-host
  mkdir -p /work/sdk/examples/wotex-matter-host/third_party/nlohmann
  curl -fsSL \
    'https://raw.githubusercontent.com/nlohmann/json/v3.11.3/single_include/nlohmann/json.hpp' \
    -o /work/sdk/examples/wotex-matter-host/third_party/nlohmann/json.hpp
  printf '#{@json_sha256}  /work/sdk/examples/wotex-matter-host/third_party/nlohmann/json.hpp\n' \
    | sha256sum -c -

  curl -fsSL \
    'https://chrome-infra-packages.appspot.com/client?platform=linux-amd64&version=git_revision:#{@cipd_revision}' \
    -o /work/tools/cipd
  printf '#{@cipd_sha256}  /work/tools/cipd\n' | sha256sum -c -
  chmod 0500 /work/tools/cipd
  printf 'gn/gn/linux-amd64 #{@gn_instance}\n' > /work/gn.ensure
  printf 'experimental/matter/zap/linux-amd64 #{@zap_instance}\n' > /work/zap.ensure
  CIPD_CACHE_DIR=/work/cipd-cache /work/tools/cipd ensure \
    -root /work/tools/gn -ensure-file /work/gn.ensure
  CIPD_CACHE_DIR=/work/cipd-cache /work/tools/cipd ensure \
    -root /work/tools/zap -ensure-file /work/zap.ensure
  printf '#{@gn_sha256}  /work/tools/gn/gn\n' | sha256sum -c -
  printf '#{@zap_cli_sha256}  /work/tools/zap/zap-cli\n' | sha256sum -c -
  /work/tools/gn/gn --version | grep -Fx '2255 (97b68a0bb62b)'
  /work/tools/zap/zap-cli --version > /work/metadata/zap.txt
  grep -F 'Version: 2026.5.12' /work/metadata/zap.txt

  git init -q /work/sdk
  test -z "$(git -C /work/sdk remote)"
  cat >> /work/sdk/BUILD.gn <<'WOTEX_GROUP'

  group("wotex-matter-host") {
    deps = [ "//examples/wotex-matter-host:wotex-matter-host" ]
  }
  WOTEX_GROUP

  cat > /work/args.gn <<'WOTEX_ARGS'
  chip_crypto = "boringssl"
  chip_config_network_layer_ble = false
  chip_enable_ble = false
  chip_inet_config_enable_ipv4 = true
  chip_build_tools = false
  chip_support_thread_meshcop = false
  chip_logging_backend = "external"
  enable_exceptions = true
  treat_warnings_as_errors = true
  target_defines = [ "CHIP_CONFIG_KVS_PATH=\\\"sdk-kvs\\\"" ]
  WOTEX_ARGS

  cp /work/args.gn /work/normal-args.gn
  cp /work/args.gn /work/sanitized-args.gn
  printf '%s\n' 'is_asan = true' 'is_ubsan = true' >> /work/sanitized-args.gn
  mkdir -p /work/build /work/build-sanitized
  cp /work/normal-args.gn /work/build/args.gn
  cp /work/sanitized-args.gn /work/build-sanitized/args.gn
  PATH=/work/tools/zap:$PATH /work/tools/gn/gn --root=/work/sdk gen /work/build
  PATH=/work/tools/zap:$PATH ninja --quiet -C /work/build wotex-matter-host
  PATH=/work/tools/zap:$PATH /work/tools/gn/gn --root=/work/sdk gen /work/build-sanitized
  PATH=/work/tools/zap:$PATH ninja --quiet -C /work/build-sanitized wotex-matter-host

  grep -F -- '-std=c++17' \
    /work/build/obj/examples/wotex-matter-host/wotex-matter-host.ninja
  cp /work/build/obj/examples/wotex-matter-host/bin/wotex-matter-host \
    /work/bin/wotex-matter-host
  cp /work/build-sanitized/obj/examples/wotex-matter-host/bin/wotex-matter-host \
    /work/bin/wotex-matter-host-sanitized
  chmod 0500 /work/bin/wotex-matter-host /work/bin/wotex-matter-host-sanitized

  cmake -S /src/native -B /work/cmake-normal -G Ninja \
    -DWOTEX_MATTER_SANITIZERS=OFF \
    -DWOTEX_MATTER_SDK_ROOT=/work/sdk \
    -DWOTEX_MATTER_JSON_INCLUDE=/work/sdk/examples/wotex-matter-host/third_party
  cmake --build /work/cmake-normal
  ctest --test-dir /work/cmake-normal --output-on-failure
  cmake -S /src/native -B /work/cmake-sanitized -G Ninja \
    -DWOTEX_MATTER_SANITIZERS=ON \
    -DWOTEX_MATTER_SDK_ROOT=/work/sdk \
    -DWOTEX_MATTER_JSON_INCLUDE=/work/sdk/examples/wotex-matter-host/third_party
  cmake --build /work/cmake-sanitized
  ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
    ctest --test-dir /work/cmake-sanitized --output-on-failure

  readelf -h /work/bin/wotex-matter-host | \
    grep -F 'Machine:                           Advanced Micro Devices X86-64'
  ldd /work/bin/wotex-matter-host > /work/metadata/needed.txt
  if grep -Eiq 'python|libssl|libcrypto|not found' /work/metadata/needed.txt; then
    exit 1
  fi
  g++ -dumpfullversion -dumpversion > /work/metadata/compiler.txt
  ld --version | head -n 1 > /work/metadata/linker.txt
  cmake --version | head -n 1 > /work/metadata/cmake.txt
  ninja --version > /work/metadata/ninja.txt
  /work/tools/gn/gn --version > /work/metadata/gn.txt
  sha256sum /usr/bin/g++ /usr/bin/ld /usr/bin/cmake /usr/bin/ninja \
    /work/tools/cipd /work/tools/gn/gn /work/tools/zap/zap-cli \
    /work/bin/wotex-matter-host /work/bin/wotex-matter-host-sanitized \
    > /work/metadata/sha256.txt
  """

  @lock_script """
  set -eu
  mkfifo /tmp/wotex-matter-controller-input
  /work/bin/wotex-matter-host < /tmp/wotex-matter-controller-input \
    > /work/results/lock-owner.stdout 2> /work/results/lock-owner.stderr &
  owner=$!
  exec 3> /tmp/wotex-matter-controller-input
  cat /work/inputs/lock-open.stdin >&3
  ready=0
  for attempt in $(seq 1 100); do
    if grep -Fq '"id":"1","ok":true' /work/results/lock-owner.stdout; then
      ready=1
      break
    fi
    sleep 0.05
  done
  test "$ready" -eq 1
  /work/bin/wotex-matter-host < /work/inputs/lock-second.stdin \
    > /work/results/lock-second.stdout 2> /work/results/lock-second.stderr
  grep -Fq '"code":"storage_open_failed"' /work/results/lock-second.stdout
  started=$(date +%s%N)
  exec 3>&-
  wait "$owner"
  finished=$(date +%s%N)
  elapsed=$((finished - started))
  printf '%s\n' "$elapsed" > /work/results/cleanup-ns.txt
  test "$elapsed" -le 1000000000
  """

  @spec main() :: :ok
  def main do
    source = File.cwd!()

    workspace =
      Path.join(System.tmp_dir!(), "wotex-matter-#{String.downcase(packet())}-native-#{unique()}")

    File.mkdir_p!(workspace)

    try do
      build!(source, workspace)
      run_acceptance!(source, workspace)
      write_manifest!(source, workspace)
      report!(workspace)
      :ok
    after
      File.rm_rf!(workspace)
    end
  end

  defp build!(source, workspace) do
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
      @build_script
    ]

    {_output, status} =
      System.cmd("docker", arguments, into: IO.stream(), stderr_to_stdout: true)

    assert!(status == 0, "WMA-#{packet()} native build failed")
  end

  defp run_acceptance!(source, workspace) do
    File.mkdir_p!(Path.join(workspace, "inputs"))
    File.mkdir_p!(Path.join(workspace, "results"))
    File.mkdir_p!(Path.join(workspace, "state"))
    File.mkdir_p!(Path.join(workspace, "empty-paa"))

    main_path = "/work/state/main"

    initial =
      run_host!(workspace, "initial", [
        flow(),
        open("1", main_path, "create_new", "generate_root"),
        request("2", "health", %{}),
        request("3", "read", %{"fabric_id" => 2}),
        request("4", "read", %{"fabric_id" => 1}),
        request("5", "close", %{})
      ])

    assert!(
      initial == [
        ready(),
        success("1", identity()),
        success("2", %{"status" => "ready", "fabric_id" => 1}),
        failure("3", "fabric_mismatch"),
        failure("4", "invalid_request"),
        success("5", nil)
      ],
      "first-party create/health/fabric/close projection differed"
    )

    assert_store_files!(workspace, "main")

    reopened =
      run_host!(workspace, "reopen", [
        flow(),
        open("1", main_path, "open_existing", "stored"),
        request("2", "close", %{})
      ])

    assert!(
      reopened == [ready(), success("1", identity()), success("2", nil)],
      "durable controller did not reopen with the same identity"
    )

    wrong_identity =
      run_host!(workspace, "wrong-identity", [
        flow(),
        open("1", main_path, "open_existing", "stored", 3)
      ])

    assert!(
      wrong_identity == [ready(), failure("1", "storage_open_failed")],
      "different controller identity did not fail before SDK startup"
    )

    partial_path = "/work/state/partial"

    partial =
      run_host!(workspace, "partial", [
        flow(),
        open("1", partial_path, "create_new", "generate_root", 2, "/work/empty-paa")
      ])

    assert!(
      partial == [ready(), failure("1", "paa_trust_store_invalid")],
      "invalid PAA startup did not fail closed"
    )

    recovered =
      run_host!(workspace, "partial-reopen", [
        flow(),
        open("1", partial_path, "open_existing", "stored")
      ])

    assert!(
      recovered == [ready(), failure("1", "controller_start_failed")],
      "partial startup retained its storage lock or regenerated incomplete state"
    )

    corrupt_authority!(workspace)

    corrupt =
      run_host!(workspace, "corrupt", [
        flow(),
        open("1", "/work/state/corrupt", "open_existing", "stored")
      ])

    assert!(
      corrupt == [ready(), failure("1", "authority_invalid")],
      "mismatched durable authority did not fail before controller setup: #{inspect(corrupt)}"
    )

    lock_and_eof!(workspace)

    after_eof =
      run_host!(workspace, "after-eof", [
        flow(),
        open("1", main_path, "open_existing", "stored"),
        request("2", "close", %{})
      ])

    assert!(
      after_eof == [ready(), success("1", identity()), success("2", nil)],
      "EOF cleanup did not release the controller and store"
    )

    operations!(workspace, main_path)
    cycles!(workspace, main_path)
    concurrent_callers!(workspace)
    sanitized!(workspace)
    assert_application_boundary!(source)
  end

  defp lock_and_eof!(workspace) do
    frames = [flow(), open("1", "/work/state/main", "open_existing", "stored")]
    write_input!(workspace, "lock-open", frames)
    write_input!(workspace, "lock-second", frames)
    {_output, status} = run_container(workspace, @lock_script)
    assert!(status == 0, "active lock or one-second EOF cleanup evidence failed")

    elapsed =
      workspace
      |> Path.join("results/cleanup-ns.txt")
      |> File.read!()
      |> String.trim()
      |> String.to_integer()

    assert!(elapsed <= 1_000_000_000, "native EOF cleanup exceeded one second")
  end

  defp operations!(workspace, path) do
    frames =
      [flow(), open("1", path, "open_existing", "stored")] ++
        Enum.map(2..1001, &request(Integer.to_string(&1), "health", %{})) ++
        [request("1002", "close", %{})]

    observed = run_host!(workspace, "operations", frames)
    assert!(length(observed) == 1003, "1000-operation lane returned the wrong count")
    assert!(hd(observed) == ready(), "1000-operation lane missed readiness")

    Enum.each(Enum.with_index(Enum.slice(observed, 2, 1000), 2), fn {frame, id} ->
      assert!(
        frame == success(Integer.to_string(id), %{"status" => "ready", "fabric_id" => 1}),
        "1000-operation correlation failed at #{id}"
      )
    end)

    assert!(
      List.last(observed) == success("1002", nil),
      "1000-operation lane did not close"
    )
  end

  defp cycles!(workspace, path) do
    write_input!(workspace, "cycle", [
      flow(),
      open("1", path, "open_existing", "stored"),
      request("2", "close", %{})
    ])

    script = """
    set -eu
    mkdir -p /work/results/cycles
    for index in $(seq 1 100); do
      /work/bin/wotex-matter-host < /work/inputs/cycle.stdin \
        > /work/results/cycles/$index.stdout \
        2> /work/results/cycles/$index.stderr
    done
    """

    {_output, status} = run_container(workspace, script)
    assert!(status == 0, "100 controller open/close cycles failed")

    Enum.each(1..100, fn index ->
      observed = decode_file!(Path.join(workspace, "results/cycles/#{index}.stdout"))

      assert!(
        observed == [ready(), success("1", identity()), success("2", nil)],
        "controller cycle #{index} differed"
      )
    end)
  end

  defp concurrent_callers!(workspace) do
    Enum.each(1..32, fn index ->
      write_input!(workspace, "stress-#{index}", [
        flow(),
        open("1", "/work/state/stress-#{index}", "create_new", "generate_root"),
        request("2", "health", %{}),
        request("3", "close", %{})
      ])
    end)

    script = """
    set -eu
    mkdir -p /work/results/stress
    pids=''
    for input in /work/inputs/stress-*.stdin; do
      name=${input##*/}
      name=${name%.stdin}
      /work/bin/wotex-matter-host < "$input" \
        > "/work/results/stress/$name.stdout" \
        2> "/work/results/stress/$name.stderr" &
      pids="$pids $!"
    done
    status=0
    for pid in $pids; do
      wait "$pid" || status=1
    done
    if find /tmp -maxdepth 1 -name 'chip_*' -print -quit | grep -q .; then
      status=1
    fi
    exit "$status"
    """

    {_output, status} = run_container(workspace, script)
    assert!(status == 0, "32 concurrent first-party controllers failed")

    Enum.each(1..32, fn index ->
      observed = decode_file!(Path.join(workspace, "results/stress/stress-#{index}.stdout"))

      assert!(
        observed == [
          ready(),
          success("1", identity()),
          success("2", %{"status" => "ready", "fabric_id" => 1}),
          success("3", nil)
        ],
        "concurrent controller #{index} differed"
      )

      assert_store_files!(workspace, "stress-#{index}")
    end)
  end

  defp sanitized!(workspace) do
    path = "/work/state/sanitized"
    options = "ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1"

    observed =
      run_host!(
        workspace,
        "sanitized",
        [
          flow(),
          open("1", path, "create_new", "generate_root"),
          request("2", "health", %{}),
          request("3", "close", %{})
        ],
        "wotex-matter-host-sanitized",
        options
      )

    assert!(
      observed == [
        ready(),
        success("1", identity()),
        success("2", %{"status" => "ready", "fabric_id" => 1}),
        success("3", nil)
      ],
      "sanitized SDK controller lifecycle differed"
    )

    failed =
      run_host!(
        workspace,
        "sanitized-failure",
        [
          flow(),
          open(
            "1",
            "/work/state/sanitized-failure",
            "create_new",
            "generate_root",
            2,
            "/work/empty-paa"
          )
        ],
        "wotex-matter-host-sanitized",
        options
      )

    assert!(
      failed == [ready(), failure("1", "paa_trust_store_invalid")],
      "sanitized startup failure differed"
    )

    eof =
      run_host!(
        workspace,
        "sanitized-eof",
        [
          flow(),
          open("1", path, "open_existing", "stored")
        ],
        "wotex-matter-host-sanitized",
        options
      )

    assert!(eof == [ready(), success("1", identity())], "sanitized EOF lifecycle differed")

    for name <- ["sanitized", "sanitized-failure", "sanitized-eof"] do
      stderr = File.read!(Path.join(workspace, "results/#{name}.stderr"))

      refute!(
        String.contains?(stderr, "ERROR: AddressSanitizer"),
        "AddressSanitizer failed in #{name}"
      )

      refute!(
        String.contains?(stderr, "runtime error:"),
        "UndefinedBehaviorSanitizer failed in #{name}"
      )
    end
  end

  defp assert_application_boundary!(source) do
    application = File.read!(Path.join(source, "mix.exs"))

    assert!(
      String.contains?(application, "def application, do: [extra_applications: []]"),
      "Matter package acquired an application callback"
    )

    refute!(
      File.exists?(Path.join(source, "lib/wotex_matter/application.ex")),
      "Matter package acquired an Application module"
    )
  end

  defp corrupt_authority!(workspace) do
    destination = Path.join(workspace, "state/corrupt")

    {output, status} =
      run_container(workspace, "cp -a /work/state/main /work/state/corrupt")

    assert!(status == 0, "could not prepare authority corruption fixture: #{output}")
    state_path = Path.join(destination, "store.json")
    state = state_path |> File.read!() |> Jason.decode!()
    encoded = get_in(state, ["values", "wotex/authority/root-cert"])
    replacement = if String.starts_with?(encoded, "A"), do: "B", else: "A"

    state =
      put_in(
        state,
        ["values", "wotex/authority/root-cert"],
        replacement <> binary_part(encoded, 1, byte_size(encoded) - 1)
      )

    File.write!(state_path, Jason.encode!(state) <> "\n")
    File.chmod!(state_path, 0o600)
  end

  defp assert_store_files!(workspace, name) do
    directory = Path.join(workspace, "state/#{name}")
    assert_mode!(directory, :directory, 0o700)
    assert_mode!(Path.join(directory, "store.json"), :regular, 0o600)
    assert_mode!(Path.join(directory, "store.lock"), :regular, 0o600)
    assert_mode!(Path.join(directory, "sdk-kvs"), :regular, 0o600)
  end

  defp assert_mode!(path, type, mode) do
    {:ok, stat} = File.lstat(path)

    assert!(
      stat.type == type && band(stat.mode, 0o777) == mode,
      "unexpected type or mode for #{Path.basename(path)}"
    )
  end

  defp run_host!(workspace, name, frames, binary \\ "wotex-matter-host", environment \\ "") do
    input = write_input!(workspace, name, frames)
    stderr = "/work/results/#{name}.stderr"
    prefix = if environment == "", do: "", else: environment <> " "
    command = "#{prefix}/work/bin/#{binary} < /work/inputs/#{Path.basename(input)} 2> #{stderr}"
    {output, status} = run_container(workspace, command)
    assert!(status == 0, "native host #{name} exited with #{status}")
    decode_lines!(output)
  end

  defp write_input!(workspace, name, frames) do
    filename = "#{name}.stdin"
    path = Path.join(workspace, "inputs/#{filename}")
    File.write!(path, Enum.join(Enum.map(frames, &Jason.encode!/1), "\n") <> "\n")
    filename
  end

  defp decode_file!(path), do: path |> File.read!() |> decode_lines!()

  defp decode_lines!(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      assert!(byte_size(line) + 1 <= 131_072, "native output exceeded the frame limit")

      case Jason.decode(line) do
        {:ok, frame} -> frame
        _ -> raise "native stdout contained a non-JSON log or malformed frame"
      end
    end)
  end

  defp run_container(workspace, command) do
    System.cmd("docker", docker_arguments(workspace, command), stderr_to_stdout: false)
  end

  defp docker_arguments(workspace, command) do
    [
      "run",
      "--rm",
      "--platform",
      "linux/amd64",
      "--volume",
      "#{workspace}:/work",
      @image,
      "bash",
      "-lc",
      command
    ]
  end

  defp flow,
    do: %{"version" => 1, "event" => "flow_open", "session_generation" => @generation}

  defp open(id, path, storage_mode, authority, node_id \\ 2, paa \\ @paa) do
    request(
      id,
      "open",
      %{
        "lifecycle" => "persistent",
        "storage_path" => path,
        "storage_mode" => storage_mode,
        "authority" => authority,
        "vendor_id" => 65_521,
        "fabric_id" => 1,
        "controller_node_id" => node_id,
        "paa_trust_store" => paa
      },
      5_000
    )
  end

  defp request(id, operation, parameters, timeout \\ 1_000),
    do: %{
      "version" => 1,
      "id" => id,
      "operation" => operation,
      "parameters" => parameters,
      "timeout_ms" => timeout
    }

  defp ready,
    do: %{
      "version" => 1,
      "event" => "ready",
      "backend" => "matter-native",
      "revision" => @sdk_revision
    }

  defp identity,
    do: %{
      "lifecycle" => "persistent",
      "fabric_id" => 1,
      "controller_node_id" => 2,
      "vendor_id" => 65_521
    }

  defp success(id, result),
    do: %{"version" => 1, "id" => id, "ok" => true, "result" => result}

  defp failure(id, code),
    do: %{"version" => 1, "id" => id, "ok" => false, "error" => %{"code" => code}}

  defp write_manifest!(source, workspace) do
    {revision, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: source)

    files =
      [
        "bin/check_p03_native.exs",
        "bin/check_p04_native.exs",
        "bin/check_p05_native.exs",
        "bin/check_p06_native.exs",
        "bin/check_p07_native.exs",
        "lib/**/*.ex",
        "native/**/*",
        "test/native/*.cpp",
        "test/wotex/matter/interaction_test.exs",
        "test/wotex/matter/persistent_bridge_test.exs",
        "test/wotex/matter/subscription_recovery_test.exs",
        "test/wotex/matter/subscription_test.exs"
      ]
      |> Enum.flat_map(&Path.wildcard(Path.join(source, &1)))
      |> Enum.filter(&File.regular?/1)
      |> Enum.sort()
      |> Enum.map(fn path ->
        %{"path" => Path.relative_to(path, source), "sha256" => sha256(path)}
      end)

    metadata = Path.join(workspace, "metadata")
    binary = Path.join(workspace, "bin/wotex-matter-host")
    sanitized = Path.join(workspace, "bin/wotex-matter-host-sanitized")

    manifest = %{
      "schema" => "wotex.native-build",
      "version" => 1,
      "package" => "wotex_matter",
      "source_revision" => String.trim(revision),
      "source_files" => files,
      "upstream_sources" => upstream_sources(),
      "toolchain" => %{
        "target" => "x86_64-linux-gnu",
        "compiler" => read_trimmed(metadata, "compiler.txt"),
        "linker" => read_trimmed(metadata, "linker.txt"),
        "cmake" => read_trimmed(metadata, "cmake.txt"),
        "ninja" => read_trimmed(metadata, "ninja.txt"),
        "gn" => read_trimmed(metadata, "gn.txt"),
        "cipd_instance" => @cipd_instance,
        "gn_instance" => @gn_instance,
        "zap_version" => @zap_version,
        "zap_instance" => @zap_instance,
        "executable_sha256" => parse_tool_hashes(metadata)
      },
      "arguments" => %{
        "gn" => String.split(String.trim(File.read!(Path.join(workspace, "args.gn"))), "\n"),
        "environment_allowlist" => ["ASAN_OPTIONS", "UBSAN_OPTIONS"]
      },
      "build_features" => [
        "boringssl",
        "controller-data-model",
        "dns-sd",
        "ipv4",
        "ipv6",
        "no-ble",
        "stderr-logging"
      ],
      "binaries" => [
        %{
          "path" => "bin/wotex-matter-host",
          "sha256" => sha256(binary),
          "elf_machine" => "Advanced Micro Devices X86-64",
          "needed_libraries" =>
            File.read!(Path.join(metadata, "needed.txt")) |> String.split("\n", trim: true)
        },
        %{
          "path" => "bin/wotex-matter-host-sanitized",
          "sha256" => sha256(sanitized),
          "elf_machine" => "Advanced Micro Devices X86-64"
        }
      ],
      "audit_results" => %{
        "cmake_normal" => "passed",
        "cmake_asan_ubsan" => "passed",
        "actual_sdk_lifecycle" => "passed",
        "operations" => 1000,
        "open_close_cycles" => 100,
        "concurrent_callers" => 32,
        "eof_cleanup_max_ns" => read_trimmed(Path.join(workspace, "results"), "cleanup-ns.txt")
      }
    }

    path = Path.join(workspace, "native-manifest.json")
    File.write!(path, Jason.encode!(manifest, pretty: true) <> "\n")
    decoded = path |> File.read!() |> Jason.decode!()
    assert!(decoded == manifest, "native manifest did not round-trip exactly")
  end

  defp upstream_sources do
    native_sources = [
      upstream("connectedhomeip", "project-chip/connectedhomeip", @sdk_revision, @sdk_sha256),
      upstream("pigweed", "google/pigweed", @pigweed_revision, @pigweed_sha256),
      upstream("boringssl", "google/boringssl", @boringssl_revision, @boringssl_sha256),
      upstream("nlassert", "nestlabs/nlassert", @nlassert_revision, @nlassert_sha256),
      upstream("nlio", "nestlabs/nlio", @nlio_revision, @nlio_sha256),
      upstream("uriparser", "uriparser/uriparser", @uriparser_revision, @uriparser_sha256),
      %{
        "name" => "nlohmann/json",
        "url" =>
          "https://raw.githubusercontent.com/nlohmann/json/v3.11.3/single_include/nlohmann/json.hpp",
        "revision" => @json_revision,
        "sha256" => @json_sha256
      }
    ]

    python_sources =
      Enum.map(@python_packages, fn {name, version, url, sha256} ->
        %{"name" => name, "url" => url, "revision" => version, "sha256" => sha256}
      end)

    native_sources ++ python_sources
  end

  defp upstream(name, repository, revision, sha256),
    do: %{
      "name" => name,
      "url" => "https://codeload.github.com/#{repository}/tar.gz/#{revision}",
      "revision" => revision,
      "sha256" => sha256
    }

  defp parse_tool_hashes(metadata) do
    metadata
    |> Path.join("sha256.txt")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Map.new(fn line ->
      [hash, path] = String.split(line, ~r/\s+/, parts: 2)
      {Path.basename(path), hash}
    end)
  end

  defp report!(workspace) do
    normal = sha256(Path.join(workspace, "bin/wotex-matter-host"))
    sanitized = sha256(Path.join(workspace, "bin/wotex-matter-host-sanitized"))
    manifest = sha256(Path.join(workspace, "native-manifest.json"))
    IO.puts("WMA-#{packet()} first-party controller lane passed")
    IO.puts("wotex-matter-host sha256 #{normal}")
    IO.puts("wotex-matter-host-sanitized sha256 #{sanitized}")
    IO.puts("native-manifest.json sha256 #{manifest}")
  end

  defp read_trimmed(directory, name),
    do: directory |> Path.join(name) |> File.read!() |> String.trim()

  defp packet, do: System.get_env("WOTEX_MATTER_NATIVE_PACKET", "P03")

  defp sha256(path) do
    path
    |> File.stream!(65_536, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, context ->
      :crypto.hash_update(context, chunk)
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp assert!(true, _message), do: :ok
  defp assert!(false, message), do: raise(message)
  defp refute!(value, message), do: assert!(!value, message)
  defp unique, do: System.unique_integer([:positive, :monotonic])
end

Wotex.Matter.Check.P03Native.main()
