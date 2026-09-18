defmodule Wotex.Workspace.NativeContainer do
  @moduledoc """
  Docker for the native checks: images built from Dockerfiles in the
  repository, the Linux container that runs Linux-only suites on other
  hosts, and the containers of suites that declare one.

  ## Images

  `image/3` builds `wotex-native-<name>:<digest>` from
  `tooling/native/docker/<name>.Dockerfile`, where `<digest>` covers the
  Dockerfile and the platform, so a changed Dockerfile builds a new image
  and an unchanged one is reused. Older tags of the same image are removed
  after a build.

  ## The Linux container

  On a host that is not Linux, a suite that requires only Linux runs in a
  container of `tooling/native/docker/linux.Dockerfile` (`linux_suite/4`),
  and so does a benchmark (`linux_task/5`): the repository is mounted
  read-only and the native cache writable, both at their host paths, and
  `tooling/native/docker/suite.sh` runs `mix wotex.native.suite` for the
  suite, or `mix wotex.native.bench` for the benchmark. Mix keeps each project's
  dependencies and build output in `<cache>/linux-container/mix`
  (`tooling/native/docker/bin/mix`). The host fetches the Hex dependencies
  of the root project and of the package into that directory first (Hex
  unpacks a package in the project directory, which is read-only in the
  container; the sources do not depend on the platform). The container's
  exit status is the suite's; for clang-tidy, the task writes the units it
  analysed to a result file the host reads.

  ## Suite containers

  A suite with `container` (`Wotex.Workspace.NativeSuite`) runs its
  `prepare` and `test` commands and clang-tidy in a container of its image
  (`start/2`, `exec_argv/3`, `stop/1`): no network, every volume and the
  suite's scratch directory mounted read-only. `to_host/2` maps a container
  path to the host file a volume mounts there, `header_filter/2` selects the
  container paths of first-party headers and `to_repository/3` rewrites
  container paths in clang-tidy output to repository-relative ones.
  """

  alias Wotex.Workspace.Exec
  alias Wotex.Workspace.NativeCache
  alias Wotex.Workspace.NativeSuite

  @docker_dir "tooling/native/docker"
  @linux_dockerfile "tooling/native/docker/linux.Dockerfile"
  @entry "tooling/native/docker/suite.sh"
  # Every suite container ends by itself after this many seconds.
  @lifetime_s 10_800

  @typedoc "A running suite container: its name, image and `{host, container}` volumes."
  @type session :: %{name: String.t(), image: String.t(), volumes: [{Path.t(), Path.t()}]}

  @doc "The Dockerfile of the Linux container, repository-relative."
  @spec linux_dockerfile() :: Path.t()
  def linux_dockerfile, do: @linux_dockerfile

  @doc """
  The image tag of repository-relative `dockerfile` for `platform`:
  `wotex-native-<name>:<digest>`.
  """
  @spec tag(Path.t(), Path.t(), String.t() | nil) :: String.t()
  def tag(root, dockerfile, platform) do
    content = File.read!(Path.join(root, dockerfile))
    digest = Base.encode16(:crypto.hash(:sha256, [content, 0, platform || ""]), case: :lower)
    "wotex-native-#{image_name(dockerfile)}:#{binary_part(digest, 0, 16)}"
  end

  @doc """
  Returns the image of `dockerfile`, building it when Docker does not have
  it.
  """
  @spec image(Path.t(), Path.t(), String.t() | nil) :: {:ok, String.t()} | {:error, String.t()}
  def image(root, dockerfile, platform) do
    cond do
      Path.dirname(dockerfile) != @docker_dir or Path.extname(dockerfile) != ".Dockerfile" ->
        {:error, "#{dockerfile}: images are built from #{@docker_dir}/<name>.Dockerfile"}

      not File.regular?(Path.join(root, dockerfile)) ->
        {:error, "#{dockerfile} not found"}

      true ->
        tag = tag(root, dockerfile, platform)
        if present?(tag), do: {:ok, tag}, else: build(root, dockerfile, platform, tag)
    end
  end

  defp image_name(dockerfile), do: Path.basename(dockerfile, ".Dockerfile")

  defp present?(tag) do
    match?({_, 0}, docker(["image", "inspect", "--format", "{{.Id}}", tag]))
  end

  defp build(root, dockerfile, platform, tag) do
    Mix.shell().info("==> building the image #{tag} from #{dockerfile}")

    argv =
      ["docker", "build" | platform_args(platform)] ++
        ["--file", Path.join(root, dockerfile), "--tag", tag, Path.join(root, @docker_dir)]

    case Exec.run(argv, cd: root, env: tool_env(), quiet: true) do
      0 ->
        prune(tag)
        {:ok, tag}

      status ->
        {:error, "docker build of #{dockerfile} failed (#{status})"}
    end
  end

  # Removes the older digest tags of the image just built.
  defp prune(tag) do
    [repository, current] = String.split(tag, ":")

    case docker(["image", "ls", repository, "--format", "{{.Tag}}"]) do
      {output, 0} ->
        for old <- String.split(output, "\n", trim: true),
            old != current and Regex.match?(~r/^[0-9a-f]{16}$/, old) do
          docker(["image", "rm", "#{repository}:#{old}"])
        end

        :ok

      _ ->
        :ok
    end
  end

  # The Linux container

  @doc """
  Runs `suite` (`:tidy` or `:test` mode) in the Linux container. For
  `:tidy`, `covered:` names the host paths (real) that earlier suites
  already give to clang-tidy; the result is `{:analysed, paths, :ok |
  :error}` with the real paths of the units the container analysed, or
  `:error` when the suite did not run.
  """
  @spec linux_suite(map(), NativeSuite.t(), :tidy | :test, keyword()) ::
          :ok | :error | {:analysed, MapSet.t(Path.t()), :ok | :error}
  def linux_suite(context, suite, mode, opts) do
    root = NativeCache.real_path(context.root)

    result =
      Path.join(NativeCache.suite_dir(context.cache, context.name, suite), "linux-result.json")

    File.mkdir_p!(Path.dirname(result))
    File.rm(result)
    covered = Keyword.get(opts, :covered, MapSet.new())
    args = linux_args(context, suite, mode, covered, result, root)

    case linux_task(context, "suite #{suite.name}", "wotex.native.suite", args,
           workspace: Keyword.get(opts, :workspace),
           requires: suite.requires
         ) do
      {:ok, status} ->
        linux_outcome(context, suite, mode, status, result, root)

      {:error, message} ->
        Mix.shell().error("#{context.name} suite #{suite.name}: #{message}")
        :error
    end
  end

  @doc """
  Runs the root task `task` for the package of `context` in the Linux
  container, as `mix TASK --package NAME ARGS...`, and returns the
  container's exit status. With `workspace:` the workspace is mounted
  writable and passed as `--workspace`. `label` (for example `"suite
  libdbus"`) names the run in messages and in the container's name. Fails
  when the image or the Mix dependencies cannot be prepared.
  """
  @spec linux_task(map(), String.t(), String.t(), [String.t()], keyword()) ::
          {:ok, non_neg_integer()} | {:error, String.t()}
  def linux_task(context, label, task, args, opts \\ []) do
    root = NativeCache.real_path(context.root)

    with {:ok, image} <- image(context.root, @linux_dockerfile, nil),
         :ok <- fetch_dependencies(context, root, context.cache) do
      {:ok,
       run_linux(context, label, [task | args], image, root,
         workspace: Keyword.get(opts, :workspace),
         requires: Keyword.get(opts, :requires, [])
       )}
    end
  end

  @doc """
  The extra `docker run` options a requirement list needs in the Linux
  container: `tun` adds the tun device and `CAP_NET_ADMIN`.
  """
  @spec run_options([String.t()]) :: [String.t()]
  def run_options(requires) do
    if "tun" in requires, do: ["--cap-add", "NET_ADMIN", "--device", "/dev/net/tun"], else: []
  end

  defp run_linux(context, label, args, image, root, opts) do
    workspace = Keyword.fetch!(opts, :workspace)
    cache = context.cache
    args = args ++ if(workspace, do: ["--workspace", workspace], else: [])

    mounts =
      [{root, root, :readonly}, {cache, cache, :writable}] ++
        if(workspace, do: [{workspace, workspace, :writable}], else: [])

    name = "wotex-native-#{context.name}-#{String.replace(label, " ", "-")}-#{random()}"

    argv =
      ["docker", "run", "--rm", "--init", "--name", name, "--workdir", root] ++
        Enum.flat_map(mounts, &mount_args/1) ++
        Enum.flat_map(linux_env(root, cache), fn {key, value} -> ["--env", "#{key}=#{value}"] end) ++
        run_options(Keyword.fetch!(opts, :requires)) ++
        [image, "sh", Path.join(root, @entry), context.name | args]

    Mix.shell().info("==> #{context.name} #{label}: in the Linux container #{image}")
    with_cleanup(name, fn -> Exec.run(argv, cd: root, env: tool_env(), quiet: true) end)
  end

  # Fetches the Hex dependencies of the root project and of the package into
  # the container's Mix state, as tooling/native/docker/bin/mix places them.
  defp fetch_dependencies(context, root, cache) do
    mix_state = Path.join([cache, "linux-container", "mix"])

    [{root, "root", nil}, {Path.join(root, context.relative), context.name, "1"}]
    |> Enum.reduce_while(:ok, fn {dir, project, path_deps}, :ok ->
      env = [
        {"MIX_DEPS_PATH", Path.join([mix_state, project, "deps"])},
        {"MIX_ENV", nil},
        {"WOTEX_PATH_DEPS", path_deps}
      ]

      case System.cmd("mix", ["deps.get", "--check-locked"],
             cd: dir,
             env: env,
             stderr_to_stdout: true
           ) do
        {_, 0} ->
          {:cont, :ok}

        {output, status} ->
          {:halt,
           {:error,
            "mix deps.get for the Linux container failed in #{Path.relative_to(dir, root)} (#{status}):\n" <>
              String.trim(output)}}
      end
    end)
  end

  defp linux_args(context, suite, :tidy, covered, result, root) do
    excluded =
      covered
      |> Enum.map(&Path.relative_to(&1, root))
      |> Enum.filter(&String.starts_with?(&1, context.relative <> "/"))
      |> Enum.sort()
      |> Enum.flat_map(&["--exclude", &1])

    ["--suite", suite.name, "--tidy", "--result", result] ++ excluded
  end

  defp linux_args(_, suite, :test, _, _, _),
    do: ["--suite", suite.name, "--test"]

  defp linux_outcome(context, suite, :test, status, _, _) do
    if status == 0 do
      :ok
    else
      Mix.shell().error(
        "#{context.name} suite #{suite.name}: the Linux container exited with status #{status}"
      )

      :error
    end
  end

  defp linux_outcome(context, suite, :tidy, status, result, root) do
    with {:ok, text} <- File.read(result),
         {:ok, %{"status" => outcome, "analysed" => analysed}} when is_list(analysed) <-
           JSON.decode(text) do
      paths = MapSet.new(analysed, &NativeCache.real_path(Path.join(root, &1)))
      {:analysed, paths, if(outcome == "ok" and status == 0, do: :ok, else: :error)}
    else
      _ ->
        Mix.shell().error(
          "#{context.name} suite #{suite.name}: the Linux container exited with status #{status} before clang-tidy ran"
        )

        :error
    end
  end

  @doc """
  The environment of the Linux container: the repository root, the native
  cache, the Mix state directory (`bin/mix`), Hex's home, a `PATH` that
  starts with the Mix wrapper, and Git's trust in the mounted repository.
  """
  @spec linux_env(Path.t(), Path.t()) :: [{String.t(), String.t()}]
  def linux_env(root, cache) do
    state = Path.join(cache, "linux-container")

    [
      {"WOTEX_ROOT", root},
      {NativeCache.variable(), cache},
      {"WOTEX_MIX_STATE", Path.join(state, "mix")},
      {"HEX_HOME", Path.join(state, "hex")},
      {"PATH",
       Path.join([root, @docker_dir, "bin"]) <>
         ":/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"},
      {"GIT_CONFIG_COUNT", "1"},
      {"GIT_CONFIG_KEY_0", "safe.directory"},
      {"GIT_CONFIG_VALUE_0", "*"}
    ]
  end

  # Suite containers

  @doc """
  Starts a container of `image` for a suite, with `volumes`
  (`{host, container}`) and `scratch` mounted read-only.
  """
  @spec start(String.t(), keyword()) :: {:ok, session()} | {:error, String.t()}
  def start(image, opts) do
    volumes = Keyword.fetch!(opts, :volumes)
    scratch = Keyword.fetch!(opts, :scratch)
    name = "wotex-native-#{random()}"
    mounts = for {host, ctr} <- [{scratch, scratch} | volumes], do: {host, ctr, :readonly}

    argv =
      ["run", "--detach", "--rm", "--init", "--network", "none", "--name", name] ++
        platform_args(Keyword.get(opts, :platform)) ++
        Enum.flat_map(mounts, &mount_args/1) ++ [image, "sleep", Integer.to_string(@lifetime_s)]

    case docker(argv) do
      {_, 0} -> {:ok, %{name: name, image: image, volumes: volumes}}
      {output, status} -> {:error, "docker run #{image} failed (#{status}): #{String.trim(output)}"}
    end
  end

  @doc "Removes the container of `session`."
  @spec stop(session()) :: :ok
  def stop(%{name: name}) do
    docker(["rm", "--force", name])
    :ok
  end

  @doc """
  The host command that runs `command` (arguments, `env`, `cd`) in the
  container of `session`.
  """
  @spec exec_argv(session(), [String.t()], keyword()) :: [String.t()]
  def exec_argv(%{name: name}, run, opts \\ []) do
    env =
      Enum.flat_map(Keyword.get(opts, :env, []), fn {key, value} -> ["--env", "#{key}=#{value}"] end)

    cd = if dir = Keyword.get(opts, :cd), do: ["--workdir", dir], else: []
    Enum.concat([["docker", "exec"], env, cd, [name | run]])
  end

  @doc "Expands the volumes of a suite container with the placeholder `values`."
  @spec volumes(NativeSuite.container(), %{String.t() => String.t()}) :: [{Path.t(), Path.t()}]
  def volumes(container, values) do
    for {host, ctr} <- container.volumes,
        do: {NativeCache.real_path(NativeSuite.expand(host, values)), ctr}
  end

  @doc """
  The host path that container path `path` (absolute) names through the
  volumes, choosing the longest matching container prefix, or `nil`.
  """
  @spec to_host([{Path.t(), Path.t()}], Path.t()) :: Path.t() | nil
  def to_host(volumes, path) do
    matching =
      Enum.filter(volumes, fn {_, ctr} ->
        path == ctr or String.starts_with?(path, ctr <> "/")
      end)

    case Enum.max_by(matching, fn {_, ctr} -> byte_size(ctr) end, fn -> nil end) do
      nil -> nil
      {host, ctr} -> host <> binary_part(path, byte_size(ctr), byte_size(path) - byte_size(ctr))
    end
  end

  @doc """
  The clang-tidy `--header-filter` for a suite container: the container
  paths of the volumes that mount a directory of the repository's packages.
  """
  @spec header_filter([{Path.t(), Path.t()}], Path.t()) :: String.t()
  def header_filter(volumes, root) do
    packages = NativeCache.real_path(Path.join(root, "packages")) <> "/"

    prefixes =
      for {host, ctr} <- volumes,
          String.starts_with?(host <> "/", packages),
          do: Regex.escape(ctr <> "/")

    "^(" <> Enum.join(prefixes, "|") <> ")"
  end

  @doc """
  Rewrites the container paths in `text` (clang-tidy output) to
  repository-relative paths: absolute ones and ones relative to
  `directory`, the working directory of the compile command.
  """
  @spec to_repository(String.t(), [{Path.t(), Path.t()}], keyword()) :: String.t()
  def to_repository(text, volumes, opts) do
    root = NativeCache.real_path(Keyword.fetch!(opts, :root))
    directory = Keyword.get(opts, :directory)

    replacements =
      volumes
      |> Enum.flat_map(fn {host, ctr} ->
        relative_host = Path.relative_to(host, root)
        relative_ctr = if directory, do: Path.relative_to(ctr, directory, force: true)
        [{ctr, relative_host} | if(relative_ctr, do: [{relative_ctr, relative_host}], else: [])]
      end)
      |> Enum.sort_by(fn {from, _} -> -byte_size(from) end)

    Enum.reduce(replacements, text, fn {from, to}, acc ->
      Regex.replace(~r/(^|[\s'"(\[])#{Regex.escape(from)}\//m, acc, "\\1#{to}/")
    end)
  end

  # Helpers

  defp mount_args({host, ctr, access}) do
    options = "type=bind,source=#{host},target=#{ctr}"
    ["--mount", if(access == :readonly, do: options <> ",readonly", else: options)]
  end

  defp platform_args(nil), do: []
  defp platform_args(platform), do: ["--platform", platform]

  # Removes the container when the caller dies before it ends.
  defp with_cleanup(name, fun) do
    owner = self()

    watcher =
      spawn(fn ->
        monitor = Process.monitor(owner)

        receive do
          :done -> :ok
          {:DOWN, ^monitor, :process, ^owner, _} -> docker(["rm", "--force", name])
        end
      end)

    try do
      fun.()
    after
      send(watcher, :done)
    end
  end

  defp docker(args) do
    System.cmd("docker", args, env: tool_env(), stderr_to_stdout: true)
  rescue
    error in ErlangError -> {Exception.message(error), 127}
  end

  defp random, do: Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

  # Docker needs no Mix or path-dependency settings of the caller.
  defp tool_env, do: [{"MIX_ENV", nil}, {"WOTEX_PATH_DEPS", nil}]
end
