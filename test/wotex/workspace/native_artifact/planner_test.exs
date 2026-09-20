defmodule Wotex.Workspace.NativeArtifact.PlannerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeArtifact.Descriptor
  alias Wotex.Workspace.NativeArtifact.Planner

  setup do
    manifest = manifest()

    descriptors = [
      descriptor("core", "production", [
        %{name: "linux", status: :supported, reason: nil},
        %{name: "device", status: :unsupported, reason: "hardware lane unavailable"}
      ]),
      descriptor("app", "production", [%{name: "linux", status: :supported, reason: nil}])
    ]

    %{manifest: manifest, descriptors: descriptors, cells: Planner.cells(descriptors, manifest)}
  end

  test "package changes retain affected dependents and explicit unsupported cells", context do
    selected = Planner.select(context.cells, context.manifest, ["packages/core/lib/core.ex"])

    assert Enum.map(selected, &{&1.package, &1.target, &1.status}) == [
             {"app", "linux", :supported},
             {"core", "device", :unsupported},
             {"core", "linux", :supported}
           ]
  end

  test "documentation-only changes produce no native cells", context do
    assert Planner.select(context.cells, context.manifest, ["docs/packages/core/specs/C.01.md"]) ==
             []

    assert Planner.select(context.cells, context.manifest, ["README.md"]) == []
  end

  test "planner changes select the declared smoke cohort", context do
    selected =
      Planner.select(context.cells, context.manifest, [
        "lib/wotex/workspace/native_artifact/planner.ex"
      ])

    assert Enum.map(selected, &{&1.package, &1.profile, &1.target}) == [
             {"core", "production", "linux"}
           ]
  end

  test "toolchain and system inputs select only cells that use them", context do
    toolchain = Planner.select(context.cells, context.manifest, ["tooling/compiler.lock"])
    assert Enum.map(toolchain, & &1.target) == ["linux", "device", "linux"]

    system = Planner.select(context.cells, context.manifest, ["systems/device.lock"])
    assert Enum.map(system, &{&1.package, &1.target}) == [{"core", "device"}]
  end

  test "manifest changes select all cells while explicit package selection is narrow", context do
    assert Planner.select(context.cells, context.manifest, ["tooling/packages.yaml"]) ==
             context.cells

    assert Enum.map(
             Planner.select(context.cells, context.manifest, [], packages: ["app"]),
             & &1.package
           ) == ["app"]
  end

  test "an unavailable diff reports fallback and uses the smoke cohort", context do
    assert {:ok, plan} =
             Planner.plan(context.descriptors, context.manifest, [],
               fallback: true,
               fallback_reason: "base revision is unavailable"
             )

    assert plan.fallback
    assert plan.fallback_reason == "base revision is unavailable"
    assert Enum.map(plan.cells, &{&1.package, &1.target}) == [{"core", "linux"}]
  end

  test "ordering and semantic slicing are deterministic and bounded", context do
    assert {:ok, first} =
             Planner.plan(context.descriptors, context.manifest, [], all: true, limit: 1)

    assert {:ok, second} =
             Planner.plan(Enum.reverse(context.descriptors), context.manifest, [],
               all: true,
               limit: 1
             )

    assert first == second
    assert Enum.all?(first.slices, &(length(&1) == 1))

    assert Enum.map(first.slices, &{hd(&1).target, hd(&1).system}) ==
             Enum.sort(Enum.map(first.slices, &{hd(&1).target, hd(&1).system}))
  end

  test "invalid limits and excessive slice expansion fail visibly", context do
    assert {:error, message} =
             Planner.plan(context.descriptors, context.manifest, [], all: true, limit: 0)

    assert message =~ "matrix limit"

    manifest = %{
      context.manifest
      | native_artifact: %{context.manifest.native_artifact | max_slices: 1}
    }

    assert {:error, message} = Planner.plan(context.descriptors, manifest, [], all: true, limit: 1)
    assert message =~ "needs 3 slices"
  end

  defp descriptor(package, profile, targets) do
    %Descriptor{
      package: package,
      profile: profile,
      kind: "executable",
      targets: targets,
      raw: %{}
    }
  end

  defp manifest do
    {:ok, manifest} =
      Manifest.from_map(%{
        "packages" => %{
          "core" => %{
            "app" => "core",
            "native" => true,
            "native_artifacts" => [%{"profile" => "production", "descriptor" => "core.json"}]
          },
          "app" => %{
            "app" => "app",
            "depends_on" => ["core"],
            "native" => true,
            "native_artifacts" => [%{"profile" => "production", "descriptor" => "app.json"}]
          }
        },
        "native_artifact" => %{
          "schema_version" => "1.0.0",
          "matrix_limit" => 8,
          "max_slices" => 8,
          "toolchains" => %{
            "compiler" => %{"identity" => "compiler-v1", "inputs" => ["tooling/compiler.lock"]}
          },
          "systems" => %{
            "host" => %{"identity" => "host-v1"},
            "device-root" => %{"identity" => "device-v1", "inputs" => ["systems/device.lock"]}
          },
          "targets" => %{
            "linux" => %{
              "operating_system" => "linux",
              "architecture" => "x86_64",
              "endianness" => "little",
              "libc" => "glibc",
              "abi" => "gnu",
              "toolchain" => "compiler",
              "system" => "host"
            },
            "device" => %{
              "operating_system" => "linux",
              "architecture" => "aarch64",
              "endianness" => "little",
              "libc" => "musl",
              "abi" => "device",
              "toolchain" => "compiler",
              "system" => "device-root"
            }
          },
          "smoke" => [%{"package" => "core", "profile" => "production", "target" => "linux"}]
        }
      })

    manifest
  end
end
