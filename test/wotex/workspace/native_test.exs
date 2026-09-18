defmodule Wotex.Workspace.NativeTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Native
  alias WotexWorkspace.Fixtures

  @manifest_map %{
    "packages" => %{
      "plain" => %{"app" => "plain", "depends_on" => []},
      "sourced" => %{
        "app" => "sourced",
        "depends_on" => [],
        "native" => true,
        "native_task" => "sourced.native.build"
      },
      "vendored" => %{"app" => "vendored", "depends_on" => [], "native" => true},
      "archived" => %{"app" => "archived", "depends_on" => [], "native" => true},
      "bare" => %{"app" => "bare", "depends_on" => [], "native" => true}
    }
  }

  defp sha(content), do: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

  setup context do
    root = Fixtures.tmp_dir(context)
    {:ok, manifest} = Manifest.from_map(@manifest_map)

    # native/<dir>/source.json shape
    Fixtures.write!(root, "packages/sourced/native/up/patches/0001.patch", "patch one\n")
    Fixtures.write!(root, "packages/sourced/native/up/vendor/lib.c", "int x;\n")

    Fixtures.write!(
      root,
      "packages/sourced/native/up/source.json",
      JSON.encode!(%{
        "schema" => "wotex.sourced.upstream-source@1",
        "version" => "4.3.5",
        "commit" => "abc123",
        "url" => "https://example.invalid/upstream.tar.gz",
        "sha256" => "0" |> String.duplicate(64),
        "patches" => [%{"path" => "patches/0001.patch", "sha256" => sha("patch one\n")}],
        "files" => %{"vendor/lib.c" => sha("int x;\n")},
        "patched_sources" => %{"src/not_here.c" => String.duplicate("1", 64)}
      })
    )

    # priv/fixtures/native-sources-v1.json shape
    Fixtures.write!(root, "packages/vendored/priv/native/patch-sdk.cmake", "cmake\n")
    Fixtures.write!(root, "packages/vendored/priv/native/vendor/y/y.c", "y\n")

    Fixtures.write!(
      root,
      "packages/vendored/priv/fixtures/native-sources-v1.json",
      JSON.encode!(%{
        "format" => "wotex.native.sources",
        "sources" => [
          %{"name" => "sdk", "version" => "1.5.7", "commit" => "d11", "url" => "u", "sha256" => "s"}
        ],
        "sdk_patches" => [%{"id" => "p", "path" => "patch-sdk.cmake", "sha256" => sha("cmake\n")}],
        "vendored_sources" => [
          %{
            "name" => "y",
            "version" => "0.12.0",
            "commit" => "8b4",
            "files" => [%{"path" => "vendor/y/y.c", "sha256" => sha("y\n")}]
          }
        ]
      })
    )

    # test/support/software/sources.json shape
    Fixtures.write!(
      root,
      "packages/archived/test/support/software/sources.json",
      JSON.encode!(%{
        "archives" => [
          %{
            "name" => "chip",
            "revision" => "250a",
            "sha256" => "x",
            "url" => "u",
            "purpose" => "native_source"
          }
        ]
      })
    )

    File.mkdir_p!(Path.join(root, "packages/bare/native"))
    %{root: root, manifest: manifest}
  end

  describe "sources/2" do
    test "reads every known shape, verifies local digests and reports absent files", %{
      root: root,
      manifest: manifest
    } do
      reports = Native.sources(manifest, root)
      assert Enum.map(reports, & &1.package) == ~w(archived bare sourced vendored)
      assert Native.sources_ok?(reports)

      sourced = Enum.find(reports, &(&1.package == "sourced"))
      assert sourced.status == :ok
      assert sourced.manifests == ["packages/sourced/native/up/source.json"]
      assert [%{name: "upstream", version: "4.3.5", commit: "abc123"}] = sourced.pins

      assert sourced.verified == [
               "packages/sourced/native/up/patches/0001.patch",
               "packages/sourced/native/up/vendor/lib.c"
             ]

      assert sourced.absent == ["packages/sourced/native/up/src/not_here.c"]

      vendored = Enum.find(reports, &(&1.package == "vendored"))
      assert vendored.status == :ok
      assert Enum.map(vendored.pins, & &1.name) == ["sdk", "y"]

      assert vendored.verified == [
               "packages/vendored/priv/native/patch-sdk.cmake",
               "packages/vendored/priv/native/vendor/y/y.c"
             ]

      archived = Enum.find(reports, &(&1.package == "archived"))
      assert archived.status == :ok
      assert [%{name: "chip", commit: "250a", version: nil}] = archived.pins
      assert archived.verified == []

      bare = Enum.find(reports, &(&1.package == "bare"))
      assert bare.status == :no_manifest
      assert bare.manifests == []
    end

    test "a digest mismatch fails the package", %{root: root, manifest: manifest} do
      File.write!(Path.join(root, "packages/sourced/native/up/patches/0001.patch"), "tampered\n")
      reports = Native.sources(manifest, root)
      refute Native.sources_ok?(reports)
      sourced = Enum.find(reports, &(&1.package == "sourced"))
      assert sourced.status == :error
      assert sourced.problems == ["packages/sourced/native/up/patches/0001.patch: sha256 mismatch"]
    end

    test "an unreadable manifest fails the package", %{root: root, manifest: manifest} do
      File.write!(Path.join(root, "packages/vendored/priv/fixtures/native-sources-v1.json"), "{")
      reports = Native.sources(manifest, root)
      vendored = Enum.find(reports, &(&1.package == "vendored"))
      # An unparsable file is not recognised as a known shape at all.
      assert vendored.status == :no_manifest
    end

    test "a source.json with an unknown schema is not a manifest", %{root: root, manifest: manifest} do
      Fixtures.write!(
        root,
        "packages/bare/native/x/source.json",
        JSON.encode!(%{"schema" => "other"})
      )

      bare = Enum.find(Native.sources(manifest, root), &(&1.package == "bare"))
      assert bare.status == :no_manifest
    end

    test "reports the pins of tooling/ after the packages", %{root: root, manifest: manifest} do
      refute Enum.any?(Native.sources(manifest, root), &(&1.package == "tooling"))

      Fixtures.write!(root, "tooling/native/bench/bench.h", "header\n")

      Fixtures.write!(
        root,
        "tooling/native/bench/source.json",
        JSON.encode!(%{
          "schema" => "wotex.tooling.bench-source@1",
          "version" => "4.6.0",
          "commit" => "b70",
          "url" => "https://example.invalid/bench.h",
          "sha256" => sha("header\n"),
          "files" => %{"bench.h" => sha("header\n"), "LICENSE" => sha("MIT\n")}
        })
      )

      reports = Native.sources(manifest, root)
      assert List.last(reports).package == "tooling"
      tooling = List.last(reports)
      assert tooling.status == :ok
      assert tooling.manifests == ["tooling/native/bench/source.json"]
      assert [%{name: "bench", version: "4.6.0", commit: "b70"}] = tooling.pins
      assert tooling.verified == ["tooling/native/bench/bench.h"]
      assert tooling.absent == ["tooling/native/bench/LICENSE"]

      Fixtures.write!(root, "tooling/native/bench/bench.h", "changed\n")
      refute Native.sources_ok?(Native.sources(manifest, root))
    end

    test "the repository pins its vendored nanobench" do
      tooling = Enum.find(Native.sources(), &(&1.package == "tooling"))
      assert tooling.status == :ok
      assert [%{name: "nanobench", version: "4.6.0"}] = tooling.pins
      assert tooling.absent == []
    end
  end

  describe "advisories/2" do
    test "queries every distinct pin and flags findings", %{root: root, manifest: manifest} do
      reports = Native.sources(manifest, root)
      pins = Native.pins(reports)
      assert Enum.map(pins, & &1.name) == ["chip", "upstream", "sdk", "y"]

      results =
        Native.advisories(reports,
          query: fn
            %{name: "sdk"} -> {:ok, [%{id: "OSV-1", summary: "bad"}]}
            %{name: "y"} -> {:error, "boom"}
            _ -> {:ok, []}
          end
        )

      refute Native.advisories_clean?(results)
      assert %{result: {:ok, [%{id: "OSV-1"}]}} = Enum.find(results, &(&1.pin.name == "sdk"))
      assert %{result: {:error, "boom"}} = Enum.find(results, &(&1.pin.name == "y"))

      clean = Native.advisories(reports, query: fn _ -> {:ok, []} end)
      assert Native.advisories_clean?(clean)
      assert Native.advisories(reports, offline: true) == []
    end

    test "osv_body/1 queries by commit when pinned, else by name and version" do
      assert Native.osv_body(%{name: "libcoap", version: "4.3.5", commit: "abc"}) == %{
               "commit" => "abc"
             }

      assert Native.osv_body(%{name: "libcoap", version: "4.3.5", commit: nil}) ==
               %{"version" => "4.3.5", "package" => %{"name" => "libcoap"}}
    end
  end

  describe "build/4" do
    test "refuses a relative workspace, an unknown package and a package without a task", %{
      root: root,
      manifest: manifest
    } do
      assert {:error, message} = Native.build("sourced", "relative/dir", manifest, root)
      assert message =~ "absolute"
      assert {:error, message} = Native.build("nope", "/tmp/ws", manifest, root)
      assert message =~ ~s(unknown package "nope")
      assert {:error, message} = Native.build("vendored", "/tmp/ws", manifest, root)
      assert message =~ "declares no native_task"
    end
  end
end
