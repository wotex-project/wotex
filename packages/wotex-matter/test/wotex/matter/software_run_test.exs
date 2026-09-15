Code.require_file("../../support/software/manifest.exs", __DIR__)
Code.require_file("../../support/software/run.exs", __DIR__)

defmodule Wotex.Matter.SoftwareRunTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter.{SoftwareManifest, SoftwareRun}

  setup do
    {temporary, 0} = System.cmd("pwd", ["-P"], cd: System.tmp_dir!())
    root = Path.join(String.trim(temporary), "wotex-run-#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    source = Path.join(root, "source")
    workspace = Path.join(root, "workspace")
    File.mkdir!(source)
    File.write!(Path.join(source, "mix.lock"), "exact locked dependencies\n")
    File.mkdir!(workspace)
    previous_path = System.get_env("PATH")
    previous_mode = System.get_env("WOTEX_PATH_DEPS")
    System.put_env("PATH", root <> ":/usr/bin:/bin")
    System.delete_env("WOTEX_PATH_DEPS")

    on_exit(fn ->
      restore("PATH", previous_path)
      restore("WOTEX_PATH_DEPS", previous_mode)
      File.rm_rf!(root)
    end)

    %{root: root, source: source, workspace: workspace}
  end

  test "a failed lane cannot pass and cleanup removes only its generated container and network",
       context do
    docker(context.root, "exit 23")
    unrelated = Path.join(context.root, "wotex-matter-run-0000000000000000")
    File.write!(unrelated, "unrelated")
    File.write!(unrelated <> ".network", "unrelated")

    assert_raise Mix.Error, "software_run_failed", fn ->
      SoftwareRun.run(context.source, context.workspace)
    end

    assert File.read!(unrelated) == "unrelated"
    [result] = Path.wildcard(Path.join(context.workspace, "run-*/software-result.json"))
    assert SoftwareManifest.read(result)["status"] == "failed"
    assert File.read!(unrelated <> ".network") == "unrelated"

    assert Enum.sort(Path.wildcard(Path.join(context.root, "wotex-matter-run-*"))) == [
             unrelated,
             unrelated <> ".network"
           ]
  end

  test "caller death reaps the in-flight Docker command and removes its owned container", context do
    docker(context.root, "printf '%s' \"$$\" > \"$root/exec.pid\"; exec /bin/sleep 60")

    {owner, monitor} =
      spawn_monitor(fn -> SoftwareRun.run(context.source, context.workspace) end)

    try do
      pid_file = Path.join(context.root, "exec.pid")
      assert eventually(fn -> File.regular?(pid_file) end)
      command_pid = File.read!(pid_file)

      [container] =
        Path.wildcard(Path.join(context.root, "wotex-matter-run-*"))
        |> Enum.reject(&String.ends_with?(&1, ".network"))

      assert File.exists?(container <> ".network")
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}, 1_000
      assert eventually(fn -> not File.exists?(container) end)
      assert eventually(fn -> not File.exists?(container <> ".network") end)

      assert eventually(fn ->
               case System.cmd("/bin/kill", ["-0", command_pid], stderr_to_stdout: true) do
                 {_, 0} -> false
                 _ -> true
               end
             end)

      assert Path.wildcard(Path.join(context.workspace, "run-*/software-result.json")) == []
    after
      Process.exit(owner, :kill)
    end
  end

  test "a result binds both exact BEAM lanes and is written after container and network cleanup",
       context do
    build_receipt(context)
    docker(context.root, acceptance(context.source, :valid))
    assert SoftwareRun.run(context.source, context.workspace) == :ok
    [path] = Path.wildcard(Path.join(context.workspace, "run-*/software-result.json"))
    result = SoftwareManifest.read(path)
    assert result["status"] == "passed"
    assert result["dependency_mode"] == "released-hex"
    assert result["dependencies"] == []
    assert result["source"] == SoftwareManifest.identity(context.source)

    assert Enum.map(result["lanes"], &Map.take(&1, ["name", "elixir", "otp", "sanitized"])) == [
             %{"name" => "current", "elixir" => "1.20.2", "otp" => "29.0.4", "sanitized" => false},
             %{"name" => "minimum", "elixir" => "1.18.4", "otp" => "27.3.4.15", "sanitized" => true}
           ]

    assert result["owned_containers_after_cleanup"] == 0
    assert result["owned_networks_after_cleanup"] == 0
    assert Path.wildcard(Path.join(context.root, "wotex-matter-run-*")) == []
    assert Bitwise.band(File.stat!(Path.dirname(path)).mode, 0o777) == 0o700

    for lane <- ~w(current minimum) do
      bootstrap = Path.join([Path.dirname(path), lane, "dependency-bootstrap", "mix.lock"])
      assert File.read!(bootstrap) == File.read!(Path.join(context.source, "mix.lock"))
      assert Bitwise.band(File.stat!(Path.dirname(bootstrap)).mode, 0o777) == 0o700
    end
  end

  test "successful command exit cannot replace a matching passing lane receipt", context do
    build_receipt(context)

    for mode <- [:absent, :failed, :wrong_source, :wrong_version] do
      docker(context.root, acceptance(context.source, mode))

      assert_raise Mix.Error, "software_run_failed", fn ->
        SoftwareRun.run(context.source, context.workspace)
      end

      assert Path.wildcard(Path.join(context.root, "wotex-matter-run-*")) == []
    end

    results = Path.wildcard(Path.join(context.workspace, "run-*/software-result.json"))
    assert length(results) == 4
    assert Enum.all?(results, &(SoftwareManifest.read(&1)["status"] == "failed"))
  end

  defp build_receipt(context) do
    for name <- SoftwareManifest.required_files("software"), name != "native-manifest.json" do
      path = Path.join(context.workspace, name)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "injected build artifact")
    end

    log = Path.join(context.workspace, "logs/test.log")
    File.mkdir!(Path.dirname(log))
    File.write!(log, "injected build result")
    source = SoftwareManifest.identity(context.source)

    SoftwareManifest.write(Path.join(context.workspace, "native-manifest.json"), %{
      "schema" => "wotex.native-build",
      "version" => 1,
      "package" => "wotex_matter",
      "source_files" => source["source_files_sha256"],
      "logs" => %{"logs/test.log" => SoftwareManifest.digest(log)}
    })

    SoftwareManifest.write(Path.join(context.workspace, "workspace-manifest.json"), %{
      "schema" => "wotex.matter.software-workspace@1",
      "status" => "ready",
      "mode" => "software",
      "sdk_revision" => SoftwareManifest.sdk_revision(),
      "sdk_archive_sha256" => SoftwareManifest.sdk_sha256(),
      "container_image" => SoftwareManifest.image(),
      "target" => "x86_64-linux-gnu",
      "source" => source,
      "files" => SoftwareManifest.file_hashes(context.workspace, "software")
    })
  end

  defp acceptance(source, mode) do
    digest =
      if mode == :wrong_source,
        do: String.duplicate("0", 64),
        else: SoftwareManifest.identity(source)["source_sha256"]

    status = if mode == :failed, do: "failed", else: "passed"
    version = if mode == :wrong_version, do: "elixir=0.0.0", else: ":"

    write =
      if mode == :absent,
        do: "exit 0",
        else: """
        directory=$(cat "$root/$name")
        mkdir "$directory/fixtures"
        #{version}
        printf '{"status":"#{status}","source_sha256":"#{digest}","elixir":"%s","otp":"%s"}\\n' "$elixir" "$otp" > "$directory/fixtures/acceptance.json"
        """

    """
    shift
    elixir=1.20.2
    otp=29.0.4
    mix_exs=
    workdir=
    while true; do
      case "$1" in
        --env)
          if test "$2" = "WOTEX_SOFTWARE_SANITIZED=true"; then elixir=1.18.4; otp=27.3.4.15; fi
          if test "$2" = "MIX_EXS=/source/wotex-matter/mix.exs"; then mix_exs=exact; fi
          shift 2
          ;;
        --workdir)
          workdir="$2"
          shift 2
          ;;
        *) break ;;
      esac
    done
    name="$1"
    shift
    directory=$(cat "$root/$name")
    case "$1:$2:$3" in
      mix:deps.get:--check-locked)
        test "$workdir" = "/run/dependency-bootstrap"
        test "$mix_exs" = "exact"
        test -f "$directory/dependency-bootstrap/mix.lock"
        ;;
      uname:-m:) printf 'x86_64\\n' ;;
      mix:run:test/support/software/lane.exs) #{write} ;;
      *) : ;;
    esac
    """
  end

  defp docker(root, execute) do
    path = Path.join(root, "docker")

    script = """
    #!/bin/sh
    root=#{quote_shell(root)}
    case "$1" in
      network)
        case "$2" in
          create) printf '%s' owned > "$root/$5.network" ;;
          rm) /bin/rm -- "$root/$3.network" ;;
          ls)
            for path in "$root"/*.network; do
              test -f "$path" || continue
              name=${path##*/}
              printf '%s\\n' "${name%.network}"
            done
            ;;
          *) exit 32 ;;
        esac
        ;;
      run)
        shift
        while test "$#" -gt 0; do
          case "$1" in
            --name) name="$2"; shift ;;
            --volume)
              case "$2" in *:/run) directory=${2%:/run} ;; esac
              shift
              ;;
          esac
          shift
        done
        printf '%s' "$directory" > "$root/$name"
        printf 'container-id\\n'
        ;;
      exec)
        #{execute}
        ;;
      rm)
        /bin/rm -- "$root/$3"
        ;;
      ps)
        name=${4#name=^}
        name=${name%?}
        if test -f "$root/$name"; then printf 'container-id\\n'; fi
        ;;
      *) exit 31 ;;
    esac
    """

    if File.exists?(path), do: File.chmod!(path, 0o700)
    File.write!(path, script)
    File.chmod!(path, 0o500)
  end

  defp eventually(predicate) do
    deadline = System.monotonic_time(:millisecond) + 2_000
    poll(predicate, deadline)
  end

  defp poll(predicate, deadline) do
    if predicate.() do
      true
    else
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(5)
        poll(predicate, deadline)
      else
        false
      end
    end
  end

  defp restore(key, nil), do: System.delete_env(key)
  defp restore(key, value), do: System.put_env(key, value)
  defp quote_shell(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"
end
