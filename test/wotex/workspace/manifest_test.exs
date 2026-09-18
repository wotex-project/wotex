defmodule Wotex.Workspace.ManifestTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.Manifest
  alias WotexWorkspace.Fixtures

  describe "from_map/2" do
    test "orders packages so that every package follows its dependencies" do
      manifest = Fixtures.manifest()

      assert Manifest.topological_order(manifest) ==
               ~w(conformance core runtime coap http lab)
    end

    test "keeps lanes and select_all_on" do
      manifest = Fixtures.manifest()

      assert {:ok, %{elixir: "1.18.4-otp-27", otp: "27.3.4.15", skip: ["formatter", "dialyzer"]}} =
               Manifest.lane("minimum", manifest)

      assert {:ok, %{skip: []}} = Manifest.lane("current", manifest)

      assert Manifest.lane("nightly", manifest) == :error
      assert "mix.exs" in manifest.select_all_on
      assert manifest.schema_version == "1.0.0"
      assert manifest.path == "fixture.yaml"
    end

    test "reads package fields" do
      manifest = Fixtures.manifest()
      coap = Manifest.fetch!("coap", manifest)
      assert coap.app == "coap"
      assert coap.native
      assert coap.native_task == "coap.native.build"
      assert coap.software_task == "coap.software.run"
      assert coap.depends_on == ["core", "runtime"]

      core = Manifest.fetch!("core", manifest)
      refute core.native
      assert core.native_task == nil
    end

    test "rejects a dependency on an unknown package" do
      map = put_in(Fixtures.manifest_map(), ["packages", "http", "depends_on"], ["core", "mqtt"])
      assert {:error, message} = Manifest.from_map(map)
      assert message =~ ~s(package http depends on unknown package "mqtt")
    end

    test "rejects a dependency cycle" do
      map =
        Fixtures.manifest_map()
        |> put_in(["packages", "core", "depends_on"], ["lab"])

      assert {:error, message} = Manifest.from_map(map, "cycle.yaml")
      assert message =~ "cycle.yaml: dependency cycle among"
      assert message =~ "core"
      assert message =~ "lab"
    end

    test "rejects malformed entries" do
      assert {:error, "missing packages"} = Manifest.from_map(%{})

      assert {:error, message} =
               Manifest.from_map(%{"packages" => %{"a" => %{"depends_on" => []}}})

      assert message =~ "app is required"

      assert {:error, message} =
               Manifest.from_map(%{"packages" => %{"Bad_Name" => %{"app" => "bad"}}})

      assert message =~ "not lowercase-with-dashes"

      assert {:error, message} =
               Manifest.from_map(%{"packages" => %{"a" => %{"app" => "a", "native" => "yes"}}})

      assert message =~ "native must be a boolean"

      assert {:error, message} =
               Manifest.from_map(%{
                 "packages" => %{"a" => %{"app" => "a"}},
                 "lanes" => %{"x" => %{}}
               })

      assert message =~ ~s(lane "x" must declare elixir and otp)
    end

    test "reads host applications with their environment" do
      map =
        put_in(Fixtures.manifest_map(), ["packages", "lab", "hosts"], [
          %{"path" => "hosts/workbench"},
          %{"path" => "hosts/nerves", "env" => %{"MIX_TARGET" => "host"}}
        ])

      assert {:ok, manifest} = Manifest.from_map(map)

      assert Manifest.fetch!("lab", manifest).hosts == [
               %Manifest.Host{path: "hosts/workbench", env: []},
               %Manifest.Host{path: "hosts/nerves", env: [{"MIX_TARGET", "host"}]}
             ]

      assert Manifest.fetch!("core", manifest).hosts == []
    end

    test "rejects hosts outside the package or with a malformed environment" do
      for hosts <- [
            %{"path" => "hosts/x"},
            [%{}],
            [%{"path" => ""}],
            [%{"path" => "/abs/host"}],
            [%{"path" => "../other"}],
            [%{"path" => "hosts/../../other"}],
            [%{"path" => "./hosts/x"}],
            [%{"path" => "hosts/x", "target" => "host"}],
            [%{"path" => "hosts/x", "env" => ["MIX_TARGET"]}],
            [%{"path" => "hosts/x", "env" => %{"mix_target" => "host"}}],
            [%{"path" => "hosts/x", "env" => %{"MIX_TARGET" => 1}}],
            [%{"path" => "hosts/x"}, %{"path" => "hosts/x"}]
          ] do
        map = put_in(Fixtures.manifest_map(), ["packages", "lab", "hosts"], hosts)
        assert {:error, message} = Manifest.from_map(map), inspect(hosts)
        assert message =~ ~r/^package lab: .*host/
      end
    end

    test "rejects a lane skip that is not a list of tool names" do
      assert {:error, message} =
               Manifest.from_map(%{
                 "packages" => %{"a" => %{"app" => "a"}},
                 "lanes" => %{"x" => %{"elixir" => "1", "otp" => "2", "skip" => [1]}}
               })

      assert message =~ ~s(lane "x": skip must list tool names)
    end
  end

  describe "graph queries" do
    setup do
      %{manifest: Fixtures.manifest()}
    end

    test "packages/1 and names/1 are sorted by name", %{manifest: manifest} do
      assert Enum.map(Manifest.packages(manifest), & &1.name) ==
               ~w(coap conformance core http lab runtime)

      assert Manifest.names(manifest) == ~w(coap conformance core http lab runtime)
    end

    test "dependents/2 lists direct dependents", %{manifest: manifest} do
      assert Manifest.dependents("core", manifest) == ~w(coap http lab runtime)
      assert Manifest.dependents("runtime", manifest) == ~w(coap http)
      assert Manifest.dependents("lab", manifest) == []
    end

    test "transitive_dependents/2 follows the graph in topological order", %{manifest: manifest} do
      assert Manifest.transitive_dependents("runtime", manifest) == ~w(coap http lab)
      assert Manifest.transitive_dependents("conformance", manifest) == ~w(lab)
      assert Manifest.transitive_dependents("core", manifest) == ~w(runtime coap http lab)
    end

    test "transitive_dependencies/2 follows the graph downwards", %{manifest: manifest} do
      assert Manifest.transitive_dependencies("lab", manifest) == ~w(conformance core runtime http)
      assert Manifest.transitive_dependencies("core", manifest) == []
    end

    test "path/2 is packages/<name>", %{manifest: manifest} do
      assert Manifest.path("coap", manifest) == "packages/coap"
      assert Manifest.absolute_path("coap", manifest, "/repo") == "/repo/packages/coap"

      assert_raise ArgumentError, ~r/unknown package "nope"/, fn ->
        Manifest.path("nope", manifest)
      end
    end

    test "in_order/2 restricts names to the topological order", %{manifest: manifest} do
      assert Manifest.in_order(~w(lab core http), manifest) == ~w(core http lab)
    end

    test "native_packages/1", %{manifest: manifest} do
      assert Enum.map(Manifest.native_packages(manifest), & &1.name) == ~w(coap lab)
    end
  end

  describe "the repository manifest" do
    test "loads, starts with wotex and ends with wotex-lab" do
      manifest = Manifest.load!()
      order = Manifest.topological_order(manifest)
      assert length(order) == 16
      assert hd(order) == "wotex"

      # Every package follows all of its dependencies.
      for name <- order, dependency <- Manifest.fetch!(name, manifest).depends_on do
        assert Enum.find_index(order, &(&1 == dependency)) < Enum.find_index(order, &(&1 == name)),
               "#{name} is ordered before its dependency #{dependency}"
      end

      # wotex-conformance is the only package that does not depend on wotex.
      assert Manifest.transitive_dependents("wotex", manifest) ==
               order -- ["wotex", "wotex-conformance"]

      assert Enum.sort(Manifest.transitive_dependents("wotex-runtime", manifest)) ==
               ~w(wotex-bacnet wotex-binding-http wotex-binding-mqtt wotex-ble wotex-coap
                  wotex-lab wotex-matter wotex-modbus wotex-opcua wotex-thread)

      assert Manifest.transitive_dependents("wotex-coap", manifest) == []
      assert {:ok, _} = Manifest.lane("minimum", manifest)
      assert {:ok, _} = Manifest.lane("current", manifest)
    end

    test "declares wotex-lab's reference hosts, each a Mix project in the package" do
      manifest = Manifest.load!()
      lab = Manifest.fetch!("wotex-lab", manifest)

      assert lab.hosts == [
               %Manifest.Host{path: "hosts/workbench", env: []},
               %Manifest.Host{path: "hosts/nerves", env: [{"MIX_TARGET", "host"}]}
             ]

      for host <- lab.hosts do
        assert File.regular?(
                 Path.join([Manifest.absolute_path("wotex-lab", manifest), host.path, "mix.exs"])
               )
      end

      assert for(package <- Manifest.packages(manifest), package.hosts != [], do: package.name) ==
               ["wotex-lab"]

      # The minimum lane skips the host gates: the hosts are applications
      # built with the current toolchain.
      assert {:ok, %{skip: skip}} = Manifest.lane("minimum", manifest)
      assert "workbench" in skip and "nerves_host" in skip
    end

    test "load/1 reports a missing file" do
      assert {:error, message} = Manifest.load("/nonexistent/packages.yaml")
      assert message =~ "/nonexistent/packages.yaml"
    end
  end
end
