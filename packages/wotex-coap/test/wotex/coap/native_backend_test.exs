defmodule Wotex.CoAP.NativeBackendTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.CoAP.{Error, NativeBackend}

  @revision "7cf7465b784baded4de183290c547d582becfd28"

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "wotex-coap-native-backend-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    executable = Path.join(root, "wotex-coap-oscore")
    manifest = Path.join(root, "native-manifest.json")
    File.write!(executable, "reviewed-native-fixture")
    File.chmod!(executable, 0o751)
    write_manifest(manifest, digest(executable))

    %{root: root, executable: executable, manifest: manifest}
  end

  test "WCO-N02 verifies ordinary executable identity without changing permissions", context do
    input = %{executable: context.executable, manifest: context.manifest}
    {:ok, before} = File.lstat(context.executable)

    assert {:ok, backend} = NativeBackend.verify(input)
    assert inspect(backend) =~ context.executable
    assert backend.executable == context.executable
    assert backend.manifest == context.manifest
    assert backend.sha256 == digest(context.executable)

    {:ok, after_verification} = File.lstat(context.executable)
    assert after_verification.mode == before.mode
  end

  test "WCO-C02 WCO-N02 rejects malformed selections before reading a backend", context do
    overlong = "/" <> String.duplicate("a", 4_096)

    for input <- [
          nil,
          %{},
          %{executable: context.executable},
          %{manifest: context.manifest},
          %{executable: context.executable, manifest: context.manifest, extra: true},
          [executable: context.executable, manifest: context.manifest],
          %{executable: "relative", manifest: context.manifest},
          %{executable: context.executable, manifest: "relative"},
          %{executable: <<47, 255>>, manifest: context.manifest},
          %{executable: context.executable <> <<0>>, manifest: context.manifest},
          %{executable: overlong, manifest: context.manifest}
        ] do
      assert_failure(input)
    end
  end

  test "WCO-N02 rejects links, directories, nonexecutables and oversized manifests", context do
    link = Path.join(context.root, "executable-link")
    manifest_link = Path.join(context.root, "manifest-link")
    nonexecutable = Path.join(context.root, "nonexecutable")
    oversized = Path.join(context.root, "oversized.json")

    File.ln_s!(context.executable, link)
    File.ln_s!(context.manifest, manifest_link)
    File.write!(nonexecutable, "fixture")
    File.chmod!(nonexecutable, 0o640)
    File.write!(oversized, :binary.copy(<<32>>, 1_048_577))

    for input <- [
          %{executable: link, manifest: context.manifest},
          %{executable: context.root, manifest: context.manifest},
          %{executable: nonexecutable, manifest: context.manifest},
          %{executable: Path.join(context.root, "missing"), manifest: context.manifest},
          %{executable: context.executable, manifest: manifest_link},
          %{executable: context.executable, manifest: context.root},
          %{executable: context.executable, manifest: Path.join(context.root, "missing.json")},
          %{executable: context.executable, manifest: oversized}
        ] do
      assert_failure(input)
    end
  end

  test "WCO-N01 WCO-N02 rejects malformed or mismatched manifest identity", context do
    expected = digest(context.executable)

    invalid = [
      "not-json",
      ~s({"schema":"wotex.coap.native@1","schema":"wotex.coap.native@1"}),
      manifest(expected, %{"schema" => "wrong"}),
      manifest(expected, %{"backend" => %{"name" => "other"}}),
      manifest(expected, %{"backend" => %{"version" => "4.3.4"}}),
      manifest(expected, %{"backend" => %{"revision" => String.duplicate("0", 40)}}),
      manifest(String.duplicate("0", 64)),
      manifest(String.upcase(expected)),
      Jason.encode!(%{
        "schema" => "wotex.coap.native@1",
        "backend" => %{"name" => "libcoap", "version" => "4.3.5", "revision" => @revision},
        "executables" => %{}
      })
    ]

    for {bytes, index} <- Enum.with_index(invalid) do
      path = Path.join(context.root, "invalid-#{index}.json")
      File.write!(path, bytes)
      assert_failure(%{executable: context.executable, manifest: path})
    end

    File.write!(context.executable, "changed-after-manifest")
    assert_failure(%{executable: context.executable, manifest: context.manifest})
  end

  defp assert_failure(input) do
    assert {:error,
            %Error{
              code: :unsupported_native_backend,
              field: :native_backend,
              class: :permanent,
              details: %{},
              effect: :none
            }} = NativeBackend.verify(input)
  end

  defp write_manifest(path, hash), do: File.write!(path, manifest(hash))

  defp manifest(hash, changes \\ %{}) do
    backend = %{"name" => "libcoap", "version" => "4.3.5", "revision" => @revision}

    %{
      "schema" => "wotex.coap.native@1",
      "backend" => backend,
      "executables" => %{"wotex-coap-oscore" => %{"sha256" => hash}},
      "build" => %{"platform" => "fixture", "features" => ["oscore"]}
    }
    |> merge_manifest(changes)
    |> Jason.encode!()
  end

  defp merge_manifest(manifest, %{"backend" => backend}) do
    Map.put(manifest, "backend", Map.merge(manifest["backend"], backend))
  end

  defp merge_manifest(manifest, changes), do: Map.merge(manifest, changes)

  defp digest(path) do
    :sha256
    |> :crypto.hash(File.read!(path))
    |> Base.encode16(case: :lower)
  end
end
