# Linux lane for the reviewed-local Bubblewrap containment profile. Runs with
# Elixir alone: `elixir bin/check_linux_containment.exs`. Requires Docker, the
# pinned base images (pulled on first build) and network access for locked Hex
# dependencies inside the lane. The Lab working tree's tracked files and each
# clean source owner's HEAD are copied into a private workspace; nothing in the
# checkouts is written. The container runs as the calling user with seccomp and
# masked system paths relaxed only so Bubblewrap can create its unprivileged
# namespaces; it is a test lane, not a hosting profile.

defmodule Wotex.Lab.Check.LinuxContainment do
  @moduledoc false

  @prefix "wotex-lab-linux-containment-"
  @deadline_ms 3_600_000
  @tests ~w(test/wotex/lab/conformance_target_process_test.exs test/wotex/lab/conformance_test.exs)

  def run do
    docker = System.find_executable("docker") || abort("docker is required for the Linux lane")
    root = Path.expand("..", __DIR__)
    dockerfile = Path.join(root, "test/containers/linux-containment/Dockerfile")
    tag = "wotex-lab-linux-containment:" <> String.slice(sha256(File.read!(dockerfile)), 0, 12)
    work = allocate!()
    name = @prefix <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    status =
      try do
        lane(docker, root, dockerfile, tag, work, name)
      after
        System.cmd(docker, ["rm", "--force", name], stderr_to_stdout: true)
        remove!(work)
      end

    status == 0 || System.halt(1)
  end

  defp lane(docker, root, dockerfile, tag, work, name) do
    copy_sources!(root, work)
    File.mkdir_p!(Path.join(work, "lane-home"))
    cmd!(docker, ["build", "--quiet", "--tag", tag, Path.dirname(dockerfile)])
    {image, 0} = System.cmd(docker, ["image", "inspect", "--format", "{{.Id}}", tag])
    packages = versions!(docker, tag)
    {uid, 0} = System.cmd("id", ["-u"])
    {gid, 0} = System.cmd("id", ["-g"])

    script =
      "mix local.hex --force && mix local.rebar --force && mix deps.get && " <>
        Enum.join(["mix", "test" | @tests] ++ ["--seed", "1"], " ")

    args =
      [
        "run",
        "--rm",
        "--pull=never",
        "--name",
        name,
        "--cpus=4",
        "--memory=4g",
        "--security-opt=seccomp=unconfined",
        "--security-opt=systempaths=unconfined",
        "--user=#{String.trim(uid)}:#{String.trim(gid)}",
        "--volume=#{work}:/work",
        "--workdir=/work/wotex-lab",
        "--env=HOME=/work/lane-home",
        "--env=CARGO_HOME=/work/lane-home/.cargo",
        "--env=MIX_ENV=test",
        "--env=WOTEX_PATH_DEPS=1",
        "--env=WOTEX_LAB_INTEGRATION=1",
        "--env=RUST_TEST_THREADS=1",
        tag,
        "sh",
        "-c",
        script
      ]

    {status, log} = stream(docker, args)
    result = Regex.run(~r/^Result: .*$/m, log) || ["Result: missing"]

    IO.puts("""
    linux containment lane: status=#{status}
      image=#{String.trim(image)} #{packages}
      tests=#{Enum.join(@tests, " ")}
      #{hd(result)}
      log_sha256=#{sha256(log)}
    """)

    status
  end

  defp copy_sources!(root, work) do
    {files, 0} = System.cmd("git", ["ls-files", "-z"], cd: root)

    for file <- String.split(files, <<0>>, trim: true), File.regular?(Path.join(root, file)) do
      target = Path.join([work, "wotex-lab", file])
      File.mkdir_p!(Path.dirname(target))
      File.cp!(Path.join(root, file), target)
    end

    index = root |> Path.join("docs/provenance/source-index.json") |> File.read!() |> JSON.decode!()

    for package <- index["packages"] do
      directory = package["repository"] |> String.split("/") |> List.last()
      Regex.match?(~r/\Awotex(?:-[a-z]+)*\z/, directory) || abort("unexpected source owner")
      repo = Path.join(Path.dirname(root), directory)
      {dirty, 0} = System.cmd("git", ["status", "--porcelain"], cd: repo)
      dirty == "" || abort("source owner has uncommitted changes: #{directory}")
      archive = Path.join(work, directory <> ".tar")
      cmd!("git", ["archive", "--format=tar", "--output", archive, "HEAD"], cd: repo)
      target = Path.join(work, directory)
      File.mkdir_p!(target)
      :ok = :erl_tar.extract(String.to_charlist(archive), cwd: String.to_charlist(target))
      File.rm!(archive)
    end
  end

  defp versions!(docker, tag) do
    {output, 0} =
      System.cmd(docker, [
        "run",
        "--rm",
        "--pull=never",
        tag,
        "sh",
        "-c",
        "dpkg-query -W -f='${Package}=${Version} ' bubblewrap gcc libc6; rustc --version | cut -d' ' -f1-2 | tr ' ' '='"
      ])

    String.trim(output)
  end

  defp stream(docker, args) do
    port =
      Port.open({:spawn_executable, docker}, [:binary, :exit_status, :stderr_to_stdout, args: args])

    collect(port, [], System.monotonic_time(:millisecond) + @deadline_ms)
  end

  defp collect(port, acc, deadline) do
    receive do
      {^port, {:data, data}} ->
        IO.binwrite(data)
        collect(port, [acc, data], deadline)

      {^port, {:exit_status, status}} ->
        {status, IO.iodata_to_binary(acc)}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        Port.close(port)
        {124, IO.iodata_to_binary(acc)}
    end
  end

  defp cmd!(executable, args, opts \\ []) do
    case System.cmd(executable, args, [stderr_to_stdout: true] ++ opts) do
      {_, 0} -> :ok
      {output, status} -> abort("#{Path.basename(executable)} failed with #{status}:\n#{output}")
    end
  end

  defp allocate! do
    base = Path.expand(System.tmp_dir!())
    path = Path.join(base, @prefix <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower))
    File.mkdir!(path)
    File.chmod!(path, 0o700)
    path
  end

  defp remove!(path) do
    base = Path.expand(System.tmp_dir!())

    if Path.dirname(path) == base and String.starts_with?(Path.basename(path), @prefix),
      do: File.rm_rf!(path),
      else: raise("refusing to remove an unowned Linux lane workspace")
  end

  defp sha256(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Lab.Check.LinuxContainment.run()
