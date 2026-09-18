defmodule Wotex.Lab.KernelContainmentTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Conformance.KernelContainment
  alias Wotex.Lab.Error

  @image "registry.example/lab/runtime@sha256:" <> String.duplicate("a", 64)

  # ExUnit's per-test directory embeds the test name, which may contain a comma
  # that runtime mount options cannot represent, so each test owns a plain one.
  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "wotex-lab-kernel-" <> Base.encode16(:crypto.strong_rand_bytes(8))
      )

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    runtime_file = Path.join(tmp_dir, "runtime-tools")
    File.write!(runtime_file, "#!/bin/sh\nexit 0\n")
    File.chmod!(runtime_file, 0o755)
    link = Path.join(tmp_dir, "runtime")
    File.ln_s!(runtime_file, link)
    archive = Path.join(tmp_dir, "subject.tar")
    File.write!(archive, "subject")
    code = Path.join(tmp_dir, "code")
    File.mkdir_p!(code)
    home = Path.join(tmp_dir, "home")
    File.mkdir_p!(home)

    runtime = %{executable: link, digest: digest(runtime_file), image: @image}
    command = ["/usr/local/bin/target", "--archive", "{subject_archive}"]

    %{runtime: runtime, command: command, archive: archive, code: code, home: home}
  end

  test "the target map hardens the container and keeps evidence path-free", context do
    assert {:ok, %{target: target, evidence: evidence, label: label}} =
             KernelContainment.external_map(
               context.runtime,
               context.command,
               context.archive,
               [context.code],
               context.home,
               timeout_ms: 10_000,
               cpu_millis: 1_500,
               memory_bytes: 134_217_728,
               processes: 32
             )

    assert label =~ ~r/\A[0-9a-f]{32}\z/
    assert target.executable == context.runtime.executable
    assert target.artifact_path == context.archive
    assert target.timeout_ms == 10_000
    assert target.environment == %{"HOME" => context.home, "LANG" => "C", "LC_ALL" => "C"}

    for flag <- [
          "run",
          "--rm",
          "--interactive",
          "--pull=never",
          "--label=wotex.lab.containment=" <> label,
          "--network=none",
          "--read-only",
          "--cap-drop=ALL",
          "--security-opt=no-new-privileges",
          "--user=65534:65534",
          "--memory=134217728",
          "--memory-swap=134217728",
          "--pids-limit=32",
          "--cpus=1.500",
          "--ulimit=core=0:0",
          "--mount=type=bind,source=#{context.archive},target=#{context.archive},readonly",
          "--mount=type=bind,source=#{context.code},target=#{context.code},readonly",
          "--entrypoint=/usr/bin/timeout"
        ] do
      assert flag in target.args
    end

    assert Enum.take(target.args, -(length(context.command) + 3)) ==
             [@image, "--signal=KILL", "7.000"] ++ context.command

    assert evidence["termination"] == "pid-namespace-init"
    assert evidence["network"] == "none"
    assert evidence["host_mounts"] == %{"mode" => "read-only", "count" => 2}
    assert evidence["runtime"]["digest"] == context.runtime.digest
    assert evidence["image"] == %{"reference" => @image, "pull" => "never"}
    assert evidence["limits"]["wall_ms"] == 7_000
    assert evidence["limits"]["runner_margin_ms"] == 3_000
    assert evidence["limits"]["swap_bytes"] == 0
    refute inspect(evidence) =~ context.home
    refute inspect(evidence) =~ context.code
    refute inspect(evidence) =~ label

    assert {:ok, %{label: other}} =
             KernelContainment.external_map(
               context.runtime,
               context.command,
               context.archive,
               [],
               context.home
             )

    assert other != label
    assert KernelContainment.profile().defaults.timeout_ms == 15_000
  end

  test "runtime, image and command admission fail before any process starts", context do
    call = fn runtime, command ->
      KernelContainment.external_map(runtime, command, context.archive, [], context.home)
    end

    changed = %{context.runtime | digest: "sha256:" <> String.duplicate("0", 64)}
    assert {:error, %Error{code: :runtime_mismatch}} = call.(changed, context.command)

    loop = Path.join(context.home, "loop")
    File.ln_s!(loop, loop)

    for runtime <- [
          %{context.runtime | executable: "relative"},
          %{context.runtime | executable: :runtime},
          %{context.runtime | executable: loop},
          %{context.runtime | executable: context.home},
          %{context.runtime | executable: context.archive},
          %{context.runtime | digest: "sha256:ABC"},
          Map.put(context.runtime, :extra, true),
          :runtime
        ] do
      assert {:error, %Error{code: code}} = call.(runtime, context.command)
      assert code in [:invalid_runtime]
    end

    for image <- [
          "lab/runtime:latest",
          "lab/runtime@sha256:abc",
          "UPPER@sha256:" <> String.duplicate("a", 64),
          1
        ] do
      assert {:error, %Error{code: :invalid_image}} =
               call.(%{context.runtime | image: image}, context.command)
    end

    for command <- [
          [],
          ["relative", "{subject_archive}"],
          ["/bin/target"],
          ["/bin/target", "{subject_archive}", "{subject_archive}"],
          ["/bin/target", "--archive={subject_archive}"],
          ["/bin/target", "{subject_archive}", "--archive={subject_archive}"],
          ["/bin/target", :atom, "{subject_archive}"],
          ["/bin/target", "{subject_archive}" | List.duplicate("x", 39)],
          :command
        ] do
      assert {:error, %Error{code: :invalid_arguments}} = call.(context.runtime, command)
    end
  end

  test "a subject-free run mounts its files and names its network variant", context do
    notebook = Path.join(context.home, "run.livemd")
    File.write!(notebook, "# run\n")
    command = ["/usr/local/lib/erlang/bin/erl", "-noshell", "-eval", "halt(0).", "-extra", notebook]

    assert {:ok, %{run: run, evidence: evidence, label: label}} =
             KernelContainment.run_map(
               context.runtime,
               command,
               [context.code, notebook],
               context.home,
               timeout_ms: 20_000
             )

    assert label =~ ~r/\A[0-9a-f]{32}\z/
    assert run.executable == context.runtime.executable
    assert run.timeout_ms == 20_000
    refute Map.has_key?(run, :artifact_path)
    assert "--network=none" in run.args
    assert "--mount=type=bind,source=#{notebook},target=#{notebook},readonly" in run.args
    assert "--mount=type=bind,source=#{context.code},target=#{context.code},readonly" in run.args
    assert List.last(run.args) == notebook
    assert evidence["network"] == "none"
    assert evidence["schema_version"] == KernelContainment.profile().version
    assert evidence["host_mounts"] == %{"mode" => "read-only", "count" => 2}
    refute inspect(evidence) =~ context.home

    assert {:ok, %{run: internal, evidence: internal_evidence}} =
             KernelContainment.run_map(
               context.runtime,
               command,
               [notebook],
               context.home,
               network: {:internal, "wotex-lab-agent-net"}
             )

    assert "--network=wotex-lab-agent-net" in internal.args
    refute "--network=none" in internal.args
    assert internal_evidence["network"] == "internal:wotex-lab-agent-net"

    for network <- [{:internal, "Bad Name"}, {:internal, ""}, :host, "none", {:internal, nil}] do
      assert {:error, %Error{code: :invalid_options}} =
               KernelContainment.run_map(context.runtime, command, [notebook], context.home,
                 network: network
               )
    end

    for subjects <- [[], :subjects, [context.code, context.code], ["relative.livemd"]] do
      assert {:error, %Error{code: :invalid_path, details: %{field: :mounts}}} =
               KernelContainment.run_map(context.runtime, command, subjects, context.home)
    end
  end

  test "files, mounts, limits and the runner argument ceiling are bounded", context do
    call = fn archive, mounts, home, opts ->
      KernelContainment.external_map(
        context.runtime,
        context.command,
        archive,
        mounts,
        home,
        opts
      )
    end

    for archive <- ["relative.tar", context.code, Path.join(context.home, "missing"), nil] do
      assert {:error, %Error{code: :invalid_path, details: %{field: :archive}}} =
               call.(archive, [], context.home, [])
    end

    comma = Path.join(context.home, "a,b")
    File.mkdir_p!(comma)

    for mounts <- [
          ["relative"],
          ["/"],
          [comma],
          [context.code, context.code],
          [Path.join(context.home, "missing")],
          [context.archive],
          [:mount],
          List.duplicate(context.code, 17),
          :mounts
        ] do
      assert {:error, %Error{code: :invalid_path, details: %{field: :mounts}}} =
               call.(context.archive, mounts, context.home, [])
    end

    for home <- ["relative", Path.join(context.home, "missing"), nil] do
      assert {:error, %Error{code: :invalid_path, details: %{field: :temporary_directory}}} =
               call.(context.archive, [], home, [])
    end

    for opts <- [
          [memory_bytes: 1],
          [processes: 1_025],
          [timeout_ms: 0],
          [cpu_millis: 99],
          [tmpfs_bytes: "16m"]
        ] do
      assert {:error, %Error{code: :invalid_limit}} = call.(context.archive, [], context.home, opts)
    end

    for opts <- [[unknown: 1], [timeout_ms: 1_000, timeout_ms: 2_000], :opts] do
      assert {:error, %Error{code: :invalid_options}} =
               call.(context.archive, [], context.home, opts)
    end

    mounts =
      for index <- 1..16 do
        path = Path.join(context.home, "mount-#{index}")
        File.mkdir_p!(path)
        path
      end

    long_command = ["/bin/target", "{subject_archive}" | List.duplicate("x", 38)]

    assert {:error, %Error{code: :invalid_arguments, details: %{arguments: count}}} =
             KernelContainment.external_map(
               context.runtime,
               long_command,
               context.archive,
               mounts,
               context.home
             )

    assert count > 64
  end

  test "residue and release refuse malformed labels and options without a runtime call",
       context do
    for label <- ["short", String.duplicate("G", 32), nil] do
      assert {:error, %Error{code: :invalid_label}} =
               KernelContainment.residue(context.runtime.executable, label,
                 temporary_directory: context.home
               )

      assert {:error, %Error{code: :invalid_label}} =
               KernelContainment.release(context.runtime.executable, label,
                 temporary_directory: context.home
               )
    end

    label = String.duplicate("a", 32)

    assert {:error, %Error{code: :invalid_path}} =
             KernelContainment.residue(context.runtime.executable, label, [])

    assert {:error, %Error{code: :invalid_options}} =
             KernelContainment.residue(context.runtime.executable, label,
               temporary_directory: context.home,
               timeout_ms: 0
             )

    assert {:error, %Error{code: :invalid_runtime}} =
             KernelContainment.residue("relative", label, temporary_directory: context.home)
  end

  # The scripted runtime answers `ps` with the container ids listed in
  # `$HOME/containers`, forgets them on `rm`, and records every argument vector.
  test "release removes labelled containers through the runtime and verifies none remain",
       context do
    label = String.duplicate("b", 32)
    File.write!(Path.join(context.home, "containers"), "c1\nc2\n")

    runtime =
      runtime_script(context.home, """
      echo "$*" >> "$HOME/calls"
      case "$1" in
        ps) cat "$HOME/containers" ;;
        rm) : > "$HOME/containers" ;;
      esac
      """)

    opts = [temporary_directory: context.home]
    assert {:ok, 2} = KernelContainment.residue(runtime, label, opts)
    assert :ok = KernelContainment.release(runtime, label, opts)
    assert {:ok, 0} = KernelContainment.residue(runtime, label, opts)
    assert :ok = KernelContainment.release(runtime, label, opts)

    ps = "ps --all --quiet --filter label=wotex.lab.containment=" <> label

    assert String.split(File.read!(Path.join(context.home, "calls")), "\n", trim: true) ==
             [ps, ps, "rm --force --volumes c1 c2", ps, ps, ps, ps]
  end

  test "a runtime that keeps containers, fails, floods or stays silent is a typed error",
       context do
    label = String.duplicate("c", 32)
    opts = [temporary_directory: context.home]
    File.write!(Path.join(context.home, "containers"), "c1\nc2\n")
    stuck = runtime_script(context.home, ~s(if [ "$1" = ps ]; then cat "$HOME/containers"; fi\n))

    assert {:error, %Error{code: :containment_residue, details: %{containers: 2}}} =
             KernelContainment.release(stuck, label, opts)

    failing = runtime_script(context.home, "exit 3\n")

    assert {:error, %Error{code: :runtime_failed, details: %{status: 3}}} =
             KernelContainment.residue(failing, label, opts)

    assert {:error, %Error{code: :runtime_failed}} =
             KernelContainment.release(failing, label, opts)

    flooding = runtime_script(context.home, "head -c 1100000 /dev/zero\n")

    assert {:error, %Error{code: :runtime_output_exceeded}} =
             KernelContainment.residue(flooding, label, opts)

    # The silent runtime waits for standard input, which stays open until the
    # deadline closes the port, so it can only ever end by that deadline.
    silent = runtime_script(context.home, "read -r _\n")

    assert {:error, %Error{code: :runtime_timeout}} =
             KernelContainment.residue(silent, label, [timeout_ms: 50] ++ opts)
  end

  defp runtime_script(home, body) do
    path = Path.join(home, "runtime-#{System.unique_integer([:positive])}")
    File.write!(path, "#!/bin/sh\n" <> body)
    File.chmod!(path, 0o755)
    path
  end

  defp digest(path),
    do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end
