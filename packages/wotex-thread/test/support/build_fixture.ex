defmodule Wotex.Thread.BuildFixture do
  @moduledoc false

  # Builds a disposable outside world for the native and software fixture builders:
  # synthetic pinned sources, recorded tool scripts and an offline transfer. The real
  # guardian, workspace, archive, patch and manifest code runs unchanged against it.

  alias Wotex.Thread.Native.{Build, Source}

  @spinel_before "(data_in[3] << 24) | (data_in[3] << 24) | (data_in[7] << 24)"
  @spinel_after "((uint32_t)data_in[3] << 24) | ((uint32_t)data_in[3] << 24) | ((uint32_t)data_in[7] << 24)"
  @discerner_before "return (static_cast<uint64_t>(1ULL) << mLength) - 1;"
  @discerner_after "return mLength == 64 ? ~static_cast<uint64_t>(0) : (static_cast<uint64_t>(1ULL) << mLength) - 1;"
  @sdk_commit "5c8c318627954c99cd1a957a290bbd4b1027d04b"

  @doc "Creates the pinned native sources, tool scripts and transfer of one disposable build."
  @spec environment(Path.t(), keyword()) :: map()
  def environment(root, options \\ []) do
    native = native_sources(root)
    downloads = downloads(root, native)

    Map.merge(Build.environment(), %{
      platform: Keyword.get(options, :platform, {:unix, :linux}),
      native: native,
      search_path: tools(root, options),
      fetch: fetch(downloads)
    })
  end

  @doc "Creates the fixture build environment with its own first-party test sources."
  @spec software_environment(Path.t(), keyword()) :: map()
  def software_environment(root, options \\ []) do
    tests = Path.join(root, "test-native")
    File.mkdir_p!(tests)
    File.write!(Path.join(tests, "protocol_test.cpp"), "int main(void) { return 0; }\n")
    Map.put(environment(root, options), :tests, Keyword.get(options, :tests, tests))
  end

  @doc "Returns the synthetic pins recorded in the disposable native sources."
  @spec pins(Path.t()) :: map()
  def pins(native), do: Jason.decode!(File.read!(Path.join(native, "dependencies.json")))

  defp native_sources(root) do
    native = Path.join(root, "priv-openthread")
    File.mkdir_p!(native)
    real = Application.app_dir(:wotex_thread, "priv/openthread")
    File.cp!(Path.join(real, "build_command.c"), Path.join(native, "build_command.c"))
    File.write!(Path.join(native, "CMakeLists.txt"), "# disposable fixture project\n")
    File.write!(Path.join(native, "dependencies.json"), Jason.encode!(synthetic_pins(root)))
    native
  end

  defp synthetic_pins(root) do
    %{
      "version" => 1,
      "sources" =>
        Map.new(sources(), fn {name, commit, repository} ->
          {name,
           %{
             "repository" => repository,
             "commit" => commit,
             "archive_sha256" => sha256_file(archive_path(root, name, commit))
           }}
        end),
      "json" => %{
        "version" => "3.11.3",
        "url" =>
          "https://raw.githubusercontent.com/nlohmann/json/v3.11.3/single_include/nlohmann/json.hpp",
        "sha256" => sha256(json_header())
      },
      "spinel_unsigned_shift_fix" => %{
        "source" => "src/lib/spinel/spinel.c",
        "before_sha256" => sha256(@spinel_before),
        "after_sha256" => sha256(@spinel_after)
      },
      "discerner_full_width_fix" => %{
        "source" => "src/core/meshcop/meshcop.hpp",
        "before_sha256" => sha256(@discerner_before),
        "after_sha256" => sha256(@discerner_after)
      }
    }
  end

  defp sources do
    [
      {"openthread", @sdk_commit, "openthread/openthread"},
      {"mbedtls", String.duplicate("a1", 20), "Mbed-TLS/mbedtls"},
      {"mbedtls-framework", String.duplicate("b2", 20), "Mbed-TLS/mbedtls-framework"}
    ]
  end

  defp downloads(root, native) do
    pins = pins(native)

    urls =
      Map.new(sources(), fn {name, commit, repository} ->
        {"https://codeload.github.com/#{repository}/tar.gz/#{commit}",
         archive_path(root, name, commit)}
      end)

    header = Path.join(root, "downloads/json.hpp")
    File.mkdir_p!(Path.dirname(header))
    File.write!(header, json_header())
    Map.put(urls, pins["json"]["url"], header)
  end

  # Each archive is created once, before the pins that bind its digest.
  defp archive_path(root, name, commit) do
    path = Path.join([root, "downloads", "#{name}-#{commit}.tar.gz"])
    unless File.regular?(path), do: create_archive(path, name, commit)
    path
  end

  defp create_archive(path, name, commit) do
    tree = Path.join(Path.dirname(path), "tree-#{name}")
    root = "#{name}-#{commit}"
    File.mkdir_p!(Path.dirname(path))
    File.rm_rf!(tree)

    files =
      case name do
        "openthread" ->
          [
            {"src/lib/spinel/spinel.c", @spinel_before},
            {"src/core/meshcop/meshcop.hpp", @discerner_before},
            {"third_party/mbedtls/README.md", "disposable\n"}
          ]

        _ ->
          [{"include/#{name}.h", "disposable #{name}\n"}]
      end

    for {relative, contents} <- files do
      file = Path.join([tree, root, relative])
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, contents)
    end

    {_, 0} =
      System.cmd("/usr/bin/tar", ["czf", path, "-C", tree, root], env: [{"PATH", "/usr/bin:/bin"}])

    File.rm_rf!(tree)
  end

  defp json_header, do: "// disposable pinned JSON header\n"

  defp fetch(downloads) do
    fn url, target, expected ->
      with {:ok, source} <- Map.fetch(downloads, url),
           :ok <- File.mkdir_p(Path.dirname(target)),
           :ok <- File.cp(source, target),
           {:ok, ^expected} <- Source.digest(target) do
        :ok
      else
        _ -> {:error, :invalid_source_download}
      end
    end
  end

  defp tools(root, options) do
    directory = Path.join(root, "tools")
    File.mkdir_p!(directory)
    missing = Keyword.get(options, :missing_tools, [])
    failing = Keyword.get(options, :failing_tool)

    for {name, script} <- scripts(failing), name not in missing do
      path = Path.join(directory, name)
      File.write!(path, script)
      File.chmod!(path, 0o755)
    end

    directory
  end

  defp scripts(failing) do
    %{
      "cmake" => cmake_script(failing == :cmake),
      "ninja" => version_script("1.11.1"),
      "cc" => compiler_script(),
      "c++" => compiler_script(),
      "readelf" => readelf_script()
    }
  end

  defp version_script(version) do
    """
    #!/bin/sh
    echo "fixture #{version}"
    exit 0
    """
  end

  # The guardian must be compiled by a real compiler; every other call only reports a version.
  defp compiler_script do
    """
    #!/bin/sh
    case "$1" in
      --version) echo "fixture compiler 12.2.0"; exit 0;;
      -dumpmachine) echo "aarch64-unknown-linux-gnu"; exit 0;;
    esac
    exec /usr/bin/cc "$@"
    """
  end

  defp readelf_script do
    """
    #!/bin/sh
    case "$1" in
      --version) echo "GNU readelf (fixture) 2.40";;
      -h) echo "ELF Header:"; echo "  Machine:                           AArch64";;
      -d) echo " 0x0000000000000001 (NEEDED)             Shared library: [libc.so.6]";;
    esac
    exit 0
    """
  end

  defp cmake_script(failing) do
    """
    #!/bin/sh
    #{if failing, do: "echo 'fixture cmake refused'; exit 3", else: ""}
    if [ "$1" = "--version" ]; then echo "cmake version 3.25.1"; exit 0; fi
    if [ "$1" = "--build" ]; then
      shift
      build=$1
      shift
      mkdir -p "$build" || exit 1
      for argument in "$@"; do
        case "$argument" in
          -j*|--target) ;;
          ot-rcp)
            mkdir -p "$build/examples/apps/ncp"
            printf '#!/bin/sh\\nexit 0\\n' > "$build/examples/apps/ncp/ot-rcp"
            chmod 755 "$build/examples/apps/ncp/ot-rcp" ;;
          *)
            printf '#!/bin/sh\\nexit 0\\n' > "$build/$argument"
            chmod 755 "$build/$argument" ;;
        esac
      done
      exit 0
    fi
    build=""
    header=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -B) shift; build=$1 ;;
        -DWOTEX_JSON_HEADER=*) header=${1#-DWOTEX_JSON_HEADER=} ;;
      esac
      shift
    done
    [ -n "$build" ] || exit 1
    mkdir -p "$build/include/nlohmann" || exit 1
    echo "fixture cache" > "$build/CMakeCache.txt"
    if [ -n "$header" ]; then cp "$header" "$build/include/nlohmann/json.hpp" || exit 1; fi
    exit 0
    """
  end

  @doc """
  Serves one HTTPS response from a generated certificate chain for `localhost`.

  Returns the URL and the client TLS options that trust only this server. The
  server answers exactly one request with `status` and `body`, then closes; a
  `:close_after` byte count truncates the body mid-transfer.
  """
  @spec https_server(non_neg_integer(), binary(), keyword()) :: {String.t(), keyword()}
  def https_server(status, body, options \\ []) do
    san = {:Extension, {2, 5, 29, 17}, false, [dNSName: ~c"localhost"]}
    key = {:rsa, 2048, 65_537}
    chain = %{root: [key: key], intermediates: [], peer: [key: key, extensions: [san]]}
    data = :public_key.pkix_test_data(%{server_chain: chain, client_chain: chain})
    {:ok, _} = Application.ensure_all_started(:ssl)

    {:ok, listen} =
      :ssl.listen(0, [:binary, active: false, reuseaddr: true] ++ data.server_config)

    {:ok, {_, port}} = :ssl.sockname(listen)
    reason = Keyword.get(options, :reason, "OK")
    sent = Keyword.get(options, :close_after, byte_size(body))

    spawn(fn ->
      with {:ok, socket} <- :ssl.transport_accept(listen, 10_000),
           {:ok, socket} <- :ssl.handshake(socket, 10_000),
           {:ok, _request} <- :ssl.recv(socket, 0, 10_000) do
        head = "HTTP/1.1 #{status} #{reason}\r\nContent-Length: #{byte_size(body)}\r\n"
        :ssl.send(socket, head <> "Connection: close\r\n\r\n" <> binary_part(body, 0, sent))
        :ssl.close(socket)
      end

      :ssl.close(listen)
    end)

    client = [
      verify: :verify_peer,
      cacerts: Keyword.fetch!(data.client_config, :cacerts),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    {"https://localhost:#{port}/source.tar.gz", client}
  end

  defp sha256(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp sha256_file(path), do: sha256(File.read!(path))
end
