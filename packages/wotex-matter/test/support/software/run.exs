Code.require_file("command.exs", __DIR__)

defmodule Wotex.Matter.SoftwareRun do
  @moduledoc false

  alias Wotex.Matter.{SoftwareCommand, SoftwareManifest}

  @lane_timeout 5_400_000
  @cleanup_timeout 30_000

  @lanes [
    %{
      "name" => "current",
      "elixir" => "1.20.2",
      "otp" => "29.0.4",
      "sanitized" => false,
      "image" =>
        "hexpm/elixir@sha256:5858ed10da646c8d82a049d2c8c23ccb29c4ecedeb04e96414be3253609689da"
    },
    %{
      "name" => "minimum",
      "elixir" => "1.18.4",
      "otp" => "27.3.4.15",
      "sanitized" => true,
      "image" =>
        "hexpm/elixir@sha256:473f77ee88977dc8cc5d05fb91080a308be86be3fc27d50aef9a837d07c8268b"
    }
  ]

  @spec run(String.t(), String.t()) :: :ok
  def run(root, workspace) do
    source = SoftwareManifest.identity(root)
    id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    directory = Path.join(workspace, "run-" <> id)
    private_directory(directory)
    dependencies = dependencies(root)
    context = %{root: root, workspace: workspace, directory: directory, dependencies: dependencies}

    try do
      lanes = Enum.map(@lanes, &lane(context, &1))
      unless SoftwareManifest.identity(root) == source, do: fail(:software_source_changed)

      SoftwareManifest.verify_local(
        root,
        workspace,
        SoftwareManifest.read(Path.join(workspace, "workspace-manifest.json")),
        :software
      )

      unless dependencies(root) == dependencies,
        do: fail(:software_dependency_source_changed)

      result = %{
        "schema" => "wotex.matter.software-run@1",
        "status" => "passed",
        "source" => source,
        "workspace_manifest_sha256" =>
          SoftwareManifest.digest(Path.join(workspace, "workspace-manifest.json")),
        "dependency_mode" => if(dependencies == [], do: "released-hex", else: "development-path"),
        "dependencies" => Enum.map(dependencies, &Map.delete(&1, "path")),
        "lanes" => lanes,
        "owned_containers_after_cleanup" => 0,
        "owned_networks_after_cleanup" => 0
      }

      SoftwareManifest.write(Path.join(directory, "software-result.json"), result)
      Mix.shell().info("Matter software acceptance passed: #{directory}")
      :ok
    rescue
      _ ->
        SoftwareManifest.write(Path.join(directory, "software-result.json"), %{
          "schema" => "wotex.matter.software-run@1",
          "status" => "failed",
          "source" => source
        })

        reraise Mix.Error, [message: "software_run_failed"], __STACKTRACE__
    end
  end

  defp lane(context, lane) do
    directory = Path.join(context.directory, lane["name"])
    private_directory(directory)

    context =
      Map.merge(context, %{
        lane: lane,
        lane_directory: directory,
        name: "wotex-matter-run-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower),
        deadline: System.monotonic_time(:millisecond) + @lane_timeout
      })

    watcher = cleanup_watcher(context.name)

    receipt =
      try do
        Mix.shell().info("Running Matter software acceptance on #{lane["name"]} BEAM")

        command(
          context,
          "network-create",
          ["network", "create", "--driver", "bridge", context.name],
          30_000
        )

        start_container(context)
        prepare(context)
        inside(context, "acceptance", ["mix", "run", "test/support/software/lane.exs"], 3_300_000)
        receipt = SoftwareManifest.read(Path.join(directory, "fixtures/acceptance.json"))

        unless receipt["status"] == "passed" and receipt["elixir"] == lane["elixir"] and
                 receipt["otp"] == lane["otp"] and
                 receipt["source_sha256"] ==
                   SoftwareManifest.identity(context.root)["source_sha256"],
               do: fail(:software_lane_receipt_mismatch)

        receipt
      after
        release_watcher(watcher)
      end

    Map.merge(lane, %{
      "status" => "passed",
      "acceptance" => receipt,
      "acceptance_sha256" =>
        SoftwareManifest.digest(Path.join(directory, "fixtures/acceptance.json")),
      "log_sha256" => SoftwareManifest.digest(Path.join(directory, "acceptance.log")),
      "owned_containers_after_cleanup" => 0,
      "owned_networks_after_cleanup" => 0
    })
  end

  defp start_container(context) do
    dependency_mounts =
      Enum.flat_map(context.dependencies, fn dependency ->
        ["--volume", dependency["path"] <> ":/source/" <> dependency["name"] <> ":ro"]
      end)

    arguments =
      [
        "run",
        "--detach",
        "--rm",
        "--init",
        "--name",
        context.name,
        "--network",
        context.name,
        "--platform",
        "linux/amd64",
        "--volume",
        context.root <> ":/source/wotex-matter:ro",
        "--volume",
        context.workspace <> ":/artifacts:ro",
        "--volume",
        context.lane_directory <> ":/run",
        "--workdir",
        "/source/wotex-matter"
      ] ++ dependency_mounts ++ [context.lane["image"], "/bin/sleep", "5400"]

    command(context, "container-start", arguments, 300_000)
  end

  defp prepare(context) do
    inside(context, "apt-update", ["apt-get", "update", "-qq"], 120_000)

    inside(
      context,
      "apt-install",
      ~w(apt-get install -y -qq libglib2.0-0 libasan8 libubsan1 procps python3),
      300_000
    )

    unless inside(context, "architecture", ["uname", "-m"], 5_000) == "x86_64\n",
      do: fail(:software_architecture_mismatch)

    inside(context, "procfs", ["test", "-d", "/proc/self/fd"], 5_000)
    inside(context, "hex", ["mix", "local.hex", "--force"], 120_000)
    inside(context, "rebar", ["mix", "local.rebar", "--force"], 120_000)
    inside(context, "dependencies", ["mix", "deps.get", "--check-locked"], 300_000)
    inside(context, "dependencies-compile", ["mix", "deps.compile"], 600_000)
    inside(context, "compile", ["mix", "compile", "--warnings-as-errors"], 120_000)
  end

  defp inside(context, id, arguments, timeout) do
    environment = %{
      "MIX_ENV" => "test",
      "MIX_HOME" => "/run/mix",
      "HEX_HOME" => "/run/hex",
      "MIX_DEPS_PATH" => "/run/deps",
      "MIX_BUILD_PATH" => "/run/build",
      "ERL_FLAGS" => "+JMsingle true +S 4:4",
      "LANG" => "C.UTF-8",
      "DEBIAN_FRONTEND" => "noninteractive",
      "WOTEX_SOFTWARE_SANITIZED" => to_string(context.lane["sanitized"]),
      "ASAN_OPTIONS" => "detect_leaks=1:halt_on_error=1",
      "UBSAN_OPTIONS" => "halt_on_error=1"
    }

    environment =
      if context.dependencies == [],
        do: environment,
        else: Map.put(environment, "WOTEX_PATH_DEPS", "1")

    arguments =
      ["exec"] ++
        Enum.flat_map(Enum.sort(environment), fn {key, value} -> ["--env", key <> "=" <> value] end) ++
        [context.name | arguments]

    command(context, id, arguments, timeout)
  end

  defp command(context, id, arguments, timeout) do
    remaining = context.deadline - System.monotonic_time(:millisecond) - @cleanup_timeout
    if remaining <= 0, do: fail(:software_lane_timeout)

    SoftwareCommand.run!("docker", arguments,
      cd: context.root,
      timeout: min(timeout, remaining),
      log: Path.join(context.lane_directory, id <> ".log")
    )
  end

  defp dependencies(root) do
    case System.get_env("WOTEX_PATH_DEPS") do
      nil ->
        []

      "1" ->
        Enum.map(~w(wotex wotex-runtime), fn name ->
          path = Path.expand("../" <> name, root)
          SoftwareManifest.assert_directories!(path)
          unless File.regular?(Path.join(path, "mix.exs")), do: fail(:software_dependency_missing)
          %{"name" => name, "path" => path, "source" => SoftwareManifest.identity(path)}
        end)

      _ ->
        fail(:software_dependency_mode)
    end
  end

  defp cleanup_watcher(name) do
    owner = self()

    spawn(fn ->
      monitor = Process.monitor(owner)

      receive do
        {:release, caller} ->
          Process.demonitor(monitor, [:flush])
          send(caller, {:container_cleanup, self(), cleanup(name)})

        {:DOWN, ^monitor, :process, ^owner, _} ->
          cleanup(name)
      end
    end)
  end

  defp release_watcher(watcher) do
    send(watcher, {:release, self()})

    receive do
      {:container_cleanup, ^watcher, :ok} -> :ok
      {:container_cleanup, ^watcher, _} -> fail(:software_container_cleanup_failed)
    after
      @cleanup_timeout -> fail(:software_container_cleanup_failed)
    end
  end

  defp cleanup(name) do
    SoftwareCommand.run("docker", ["rm", "--force", name], timeout: 5_000)

    container =
      SoftwareCommand.run(
        "docker",
        ["ps", "--all", "--filter", "name=^" <> name <> "$", "--format", "{{.ID}}"],
        timeout: 5_000
      )

    SoftwareCommand.run("docker", ["network", "rm", name], timeout: 5_000)

    networks =
      SoftwareCommand.run("docker", ["network", "ls", "--format", "{{.Name}}"], timeout: 5_000)

    case {container, networks} do
      {{:ok, ""}, {:ok, names}} ->
        if name in String.split(names, "\n", trim: true), do: :error, else: :ok

      _ ->
        :error
    end
  end

  defp private_directory(path) do
    File.mkdir!(path)
    File.chmod!(path, 0o700)
  end

  defp fail(code), do: Mix.raise(Atom.to_string(code))
end
