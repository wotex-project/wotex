# The Matter controller against the pinned connectedhomeip example peer, run by
# `mix native.bench --package wotex-matter --bench controller_peer --workspace DIR`
# after the package's native build verified DIR. The controller host and the
# peers are x86_64 Linux executables that `mix wotex.software.build` builds in
# the pinned linux/amd64 container, so this script runs the measurement where
# the software lane runs its acceptance cases (test/support/software/run.exs):
# in a linux/amd64 hexpm/elixir container on a private Docker network, with the
# package source and the workspace mounted read-only. There,
# bench/native/support/controller_peer.exs starts the all-clusters peer,
# commissions it through the public API and writes the report, which this
# script copies to WOTEX_BENCH_OUTPUT.
Code.require_file("../../test/support/software/manifest.exs", __DIR__)
Code.require_file("../../test/support/software/command.exs", __DIR__)

defmodule Wotex.Matter.Bench.ControllerPeer do
  @moduledoc false

  alias Wotex.Matter.{SoftwareCommand, SoftwareManifest}

  # The image of the software lane's current BEAM (test/support/software/run.exs).
  @image "hexpm/elixir@sha256:5858ed10da646c8d82a049d2c8c23ccb29c4ecedeb04e96414be3253609689da"
  @siblings ~w(wotex wotex-runtime)
  @script "bench/native/support/controller_peer.exs"

  @spec main() :: :ok
  def main do
    root = Path.expand("../..", __DIR__)
    workspace = System.fetch_env!("WOTEX_MATTER_BENCH_WORKSPACE")
    run = Path.join(System.fetch_env!("WOTEX_MATTER_BENCH_SCRATCH"), "run")
    verify(root, workspace)
    File.mkdir_p!(Path.join(run, "dependency-bootstrap"))
    File.cp!(Path.join(root, "mix.lock"), Path.join(run, "dependency-bootstrap/mix.lock"))
    name = "wotex-matter-bench-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
    context = %{root: root, run: run, name: name, path_deps: path_deps(root)}

    try do
      docker(context, "network-create", ["network", "create", "--driver", "bridge", name], 30_000)
      start(context, workspace)
      prepare(context)

      # The controller host writes the SDK's log to its inherited stderr, far
      # beyond a command's output bound; it goes to a file beside the logs.
      stderr = ~s(exec "$@" 2>/run/benchmark-stderr.log)

      inside(context, "benchmark", ["sh", "-c", stderr, "sh", "mix", "run", @script], 1_800_000,
        env: %{
          "WOTEX_BENCH_OUTPUT" => "/run/report.md",
          "WOTEX_BENCH_TITLE" => System.fetch_env!("WOTEX_BENCH_TITLE"),
          "WOTEX_BENCH_DESCRIPTION" => System.fetch_env!("WOTEX_BENCH_DESCRIPTION")
        }
      )

      Mix.shell().info(File.read!(Path.join(run, "benchmark.log")))
      File.cp!(Path.join(run, "report.md"), System.fetch_env!("WOTEX_BENCH_OUTPUT"))
      :ok
    after
      SoftwareCommand.run("docker", ["rm", "--force", name], timeout: 30_000)
      SoftwareCommand.run("docker", ["network", "rm", name], timeout: 30_000)
    end
  end

  # The native build accepts a native-only workspace; the peers need the
  # software build of the same source.
  defp verify(root, workspace) do
    manifest = SoftwareManifest.read(Path.join(workspace, "workspace-manifest.json"))
    SoftwareManifest.verify_local(root, workspace, manifest, :software)
  rescue
    error in Mix.Error ->
      Mix.raise(
        "controller_peer needs the peers of a software build of this source (#{error.message}); " <>
          "run `mix pkg wotex-matter wotex.software.build --workspace #{workspace}` first"
      )
  end

  defp path_deps(root) do
    if System.get_env("WOTEX_PATH_DEPS") == "1",
      do: Enum.map(@siblings, &{&1, Path.expand("../" <> &1, root)}),
      else: []
  end

  defp start(context, workspace) do
    siblings =
      Enum.flat_map(context.path_deps, fn {name, path} ->
        ["--volume", path <> ":/source/" <> name <> ":ro"]
      end)

    arguments =
      ["run", "--detach", "--rm", "--init", "--name", context.name, "--network", context.name] ++
        ["--platform", "linux/amd64", "--volume", context.root <> ":/source/wotex-matter:ro"] ++
        ["--volume", workspace <> ":/artifacts:ro", "--volume", context.run <> ":/run"] ++
        siblings ++ ["--workdir", "/source/wotex-matter", @image, "/bin/sleep", "7200"]

    docker(context, "container-start", arguments, 600_000)
  end

  defp prepare(context) do
    inside(context, "apt-update", ~w(apt-get update -qq), 300_000)
    inside(context, "apt-install", ~w(apt-get install -y -qq libglib2.0-0 procps), 600_000)
    inside(context, "hex", ~w(mix local.hex --force), 300_000)
    inside(context, "rebar", ~w(mix local.rebar --force), 300_000)

    inside(context, "dependencies", ~w(mix deps.get --check-locked), 600_000,
      workdir: "/run/dependency-bootstrap",
      env: %{"MIX_EXS" => "/source/wotex-matter/mix.exs"}
    )

    inside(context, "dependencies-compile", ~w(mix deps.compile), 1_800_000)
    inside(context, "compile", ~w(mix compile), 600_000)
  end

  defp inside(context, id, arguments, timeout, options \\ []) do
    environment =
      %{
        "MIX_ENV" => "dev",
        "MIX_HOME" => "/run/mix",
        "HEX_HOME" => "/run/hex",
        "MIX_DEPS_PATH" => "/run/deps",
        "MIX_BUILD_PATH" => "/run/build",
        # The default dual-mapped JIT does not start under Rosetta translation.
        "ERL_FLAGS" => "+JMsingle true",
        "LANG" => "C.UTF-8",
        "DEBIAN_FRONTEND" => "noninteractive"
      }
      |> Map.merge(if context.path_deps == [], do: %{}, else: %{"WOTEX_PATH_DEPS" => "1"})
      |> Map.merge(Keyword.get(options, :env, %{}))

    workdir = if options[:workdir], do: ["--workdir", options[:workdir]], else: []

    variables =
      Enum.flat_map(Enum.sort(environment), fn {key, value} -> ["--env", key <> "=" <> value] end)

    docker(
      context,
      id,
      Enum.concat([["exec"], variables, workdir, [context.name | arguments]]),
      timeout
    )
  end

  defp docker(context, id, arguments, timeout) do
    log = Path.join(context.run, id <> ".log")
    Mix.shell().info("==> controller_peer: #{id}")

    case SoftwareCommand.run("docker", arguments, timeout: timeout, log: log) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Mix.raise("controller_peer #{id} failed (#{reason}); see #{log} and #{context.run}")
    end
  end
end

Wotex.Matter.Bench.ControllerPeer.main()
