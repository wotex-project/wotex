defmodule Wotex.Lab.ConformanceContainmentTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Conformance.{Containment, Target}
  alias Wotex.Lab.Error

  # Pure admission, derivation and evidence cases. The operator-provisioned
  # launcher is replaced by a digest-pinned stub that is never executed; the
  # cases that run a contained process live in `Wotex.Lab.ConformanceTest`
  # behind the integration tag together with the native build.
  setup_all do
    home =
      Path.join(System.tmp_dir!(), "wotex-lab-containment-#{System.unique_integer([:positive])}")

    File.mkdir_p!(home)

    archive = Path.join(home, "subject.tar")
    File.write!(archive, "subject archive bytes")

    launcher = Path.join(home, "wotex-contained-exec")
    File.write!(launcher, "#!/bin/sh\nexit 0\n")
    File.chmod!(launcher, 0o755)

    probe = Path.join(home, "containment-probe")
    File.write!(probe, "#!/bin/sh\nexit 0\n")
    File.chmod!(probe, 0o755)

    digest =
      "sha256:" <> Base.encode16(:crypto.hash(:sha256, File.read!(launcher)), case: :lower)

    on_exit(fn -> File.rm_rf!(home) end)

    %{
      home: home,
      archive: archive,
      probe: probe,
      launcher: %{executable: launcher, digest: digest}
    }
  end

  test "the derivation is pure and reports unsupported operations and non-object documents" do
    request = fn operation, input ->
      %{"claim" => %{"operation" => operation}, "vector" => %{"id" => "v", "input" => input}}
    end

    document = %{
      "@context" => Wotex.td_context_1_1(),
      "title" => "Lamp",
      "security" => ["nosec_sc"],
      "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}}
    }

    assert %{
             "outcome" => "observed",
             "actual" => %{"accepted" => true, "document" => %{"/title" => "Lamp"}}
           } =
             Target.respond(
               request.("thing_description.parse", %{
                 "document" => document,
                 "projection" => ["/title", "/missing"]
               })
             )

    assert %{"actual" => %{"accepted" => true, "document" => ^document}} =
             Target.respond(
               request.("thing_description.validate", %{"document" => document, "projection" => []})
             )

    assert %{
             "actual" => %{
               "accepted" => false,
               "errors" => [
                 %{"code" => "schema_violation", "path" => "/title", "phase" => "schema"}
               ]
             }
           } =
             Target.respond(
               request.("thing_description.validate", %{
                 "document" => Map.delete(document, "title"),
                 "projection" => []
               })
             )

    assert %{"actual" => %{"accepted" => false, "errors" => [%{"code" => "object_required"}]}} =
             Target.respond(request.("thing_model.parse", %{"document" => "not-an-object"}))

    assert %{"outcome" => "unsupported", "codes" => ["operation_not_implemented"]} =
             Target.respond(request.("discovery.list", %{}))

    assert %{"outcome" => "unsupported", "codes" => ["invalid_request"]} = Target.respond(%{})
  end

  test "the process entry maps argument, input and decoding failures to exit codes", context do
    request = ~s({"claim":{"operation":"discovery.list"},"vector":{"id":"v","input":{}}})
    assert {:ok, encoded} = Target.run(["--archive", context.archive], fn -> request <> "\n" end)
    assert encoded =~ ~s("outcome":"unsupported")
    assert {:error, 11} = Target.run([], fn -> request end)

    assert {:error, 12} =
             Target.run(["--archive", Path.join(context.home, "missing")], fn -> request end)

    assert {:error, 13} = Target.run(["--archive", context.archive], fn -> :eof end)
    assert {:error, 14} = Target.run(["--archive", context.archive], fn -> "[not an object]" end)
    assert {:error, 14} = Target.run(["--archive", context.archive], fn -> "{" end)
  end

  test "the host profile is path-free evidence for inherited resource and network limits",
       context do
    result =
      Containment.external_map(
        context.probe,
        ["probe", "{subject_archive}"],
        context.archive,
        context.home,
        memory_bytes: 1_073_741_824,
        processes: 512,
        launcher: context.launcher
      )

    if sandbox_available?() do
      assert {:ok, %{target: config, evidence: evidence}} = result

      assert evidence["kind"] == "wotex_lab_conformance_containment"
      assert evidence["network"] == "denied"
      assert evidence["temporary_directory"] == "private"
      assert evidence["termination"] == "process_group"
      assert evidence["schema_version"] == "2.0.2"
      assert evidence["mechanism"] in ["darwin-sandbox-exec", "linux-bubblewrap"]
      assert evidence["limits"]["memory_bytes"] == 1_073_741_824
      assert evidence["limits"]["processes"] == 512
      assert evidence["limits"]["wall_ms"] == 9_000
      assert evidence["limits"]["runner_timeout_ms"] == 10_000
      assert evidence["limits"]["runner_margin_ms"] == 1_000
      assert evidence["limits"]["cleanup_reserve_ms"] == 150
      assert evidence["limits"]["output_bytes"] == 1_048_576
      refute inspect(evidence) =~ context.home
      refute inspect(evidence) =~ context.probe
      assert evidence["launcher"]["implementation"] == "rust-executable"
      assert evidence["launcher"]["version"] == "2.0.0"
      assert evidence["launcher"]["digest"] == context.launcher.digest

      assert config.artifact_path == context.archive
      assert config.timeout_ms == 10_000
      assert config.max_output_bytes == 1_048_576
      assert config.environment["HOME"] == context.home
      assert config.environment["LANG"] == "C.UTF-8"
      assert Path.type(config.executable) == :absolute

      launcher_args = Enum.drop_while(config.args, &(&1 != context.launcher.executable))

      assert [
               _,
               "--wall-ms",
               "9000",
               "--cpu-seconds",
               "8",
               "--memory-bytes",
               "1073741824",
               "--processes",
               "512",
               "--open-files",
               "128",
               "--file-size-bytes",
               "1048576",
               "--temp-dir",
               temp_dir,
               "--",
               probe,
               "probe",
               "{subject_archive}"
             ] = launcher_args

      assert temp_dir == context.home
      assert probe == context.probe
    else
      assert {:error, %Error{code: :unsupported, phase: :containment}} = result
    end
  end

  test "invalid containment inputs are refused before a target starts", context do
    valid_args = ["{subject_archive}"]
    assert Containment.profile().version == "2.0.2"

    assert {:error, %Error{code: :invalid_path}} =
             Containment.external_map("relative", valid_args, context.archive, context.home)

    assert {:error, %Error{code: :invalid_path}} =
             Containment.external_map("mix.exs", valid_args, context.archive, context.home)

    assert {:error, %Error{code: :invalid_path}} =
             Containment.external_map(context.archive, valid_args, context.archive, context.home)

    assert {:error, %Error{code: :invalid_path}} =
             Containment.external_map(context.probe, valid_args, 1, context.home)

    assert {:error, %Error{code: :invalid_path}} =
             Containment.external_map(context.probe, valid_args, context.archive, "relative")

    assert {:error, %Error{code: :invalid_path}} =
             Containment.external_map(context.probe, valid_args, context.archive, 1)

    assert {:error, %Error{code: :invalid_path}} =
             Containment.external_map(
               context.probe,
               valid_args,
               context.archive,
               Path.join(context.home, "missing")
             )

    unsafe = Path.join(context.home, "unsafe\"directory")
    File.mkdir!(unsafe)

    assert {:error, %Error{code: :invalid_path}} =
             Containment.external_map(context.probe, valid_args, context.archive, unsafe)

    assert {:error, %Error{code: :invalid_arguments}} =
             Containment.external_map(context.probe, [], context.archive, context.home)

    assert {:error, %Error{code: :invalid_arguments}} =
             Containment.external_map(context.probe, "archive", context.archive, context.home)

    for args <- [
          [1, "{subject_archive}"],
          [String.duplicate("x", 4_097), "{subject_archive}"],
          ["{subject_archive}", "{subject_archive}"],
          Enum.reverse(["{subject_archive}" | List.duplicate("argument", 28)])
        ] do
      assert {:error, %Error{code: :invalid_arguments}} =
               Containment.external_map(context.probe, args, context.archive, context.home)
    end

    assert {:error, %Error{code: :invalid_arguments}} =
             Containment.external_map(
               context.probe,
               ["prefix-{subject_archive}"],
               context.archive,
               context.home
             )

    assert {:error, %Error{code: :invalid_limit, details: %{limit: :memory_bytes}}} =
             Containment.external_map(
               context.probe,
               valid_args,
               context.archive,
               context.home,
               memory_bytes: 1
             )

    assert {:error, %Error{code: :invalid_options}} =
             Containment.external_map(
               context.probe,
               valid_args,
               context.archive,
               context.home,
               shell: true
             )

    assert {:error, %Error{code: :invalid_options}} =
             Containment.external_map(
               context.probe,
               valid_args,
               context.archive,
               context.home,
               [1]
             )

    assert {:error, %Error{code: :invalid_options}} =
             Containment.external_map(
               context.probe,
               valid_args,
               context.archive,
               context.home,
               timeout_ms: 1_000,
               timeout_ms: 2_000
             )

    assert {:error, %Error{code: :invalid_limit, details: %{limit: :timeout_ms}}} =
             Containment.external_map(
               context.probe,
               valid_args,
               context.archive,
               context.home,
               timeout_ms: 120_001
             )
  end

  test "short runner deadlines retain a positive fail-safe inner deadline", context do
    result =
      Containment.external_map(
        context.probe,
        ["{subject_archive}"],
        context.archive,
        context.home,
        timeout_ms: 1_000,
        launcher: context.launcher
      )

    if sandbox_available?() do
      assert {:ok, %{target: config, evidence: evidence}} = result
      assert config.timeout_ms == 1_000
      assert evidence["limits"]["wall_ms"] == 1
      assert evidence["limits"]["runner_margin_ms"] == 999
      assert evidence["limits"]["cleanup_reserve_ms"] == 150
    else
      assert {:error, %Error{code: :unsupported}} = result
    end
  end

  test "a non-symlinked private directory reaches the admitted sandbox", context do
    directory = Path.join(File.cwd!(), ".containment-#{System.unique_integer([:positive])}")
    File.mkdir!(directory)
    on_exit(fn -> File.rmdir(directory) end)

    result =
      Containment.external_map(
        context.probe,
        ["{subject_archive}"],
        context.archive,
        directory,
        launcher: context.launcher
      )

    case {sandbox_available?(), :os.type()} do
      {true, {:unix, :darwin}} ->
        assert {:ok, %{target: config}} = result
        assert config.executable == "/usr/bin/sandbox-exec"
        assert Enum.at(config.args, 0) == "-p"
        assert Enum.at(config.args, 1) =~ "(deny network*)"
        assert Enum.at(config.args, 1) =~ "(subpath \"#{directory}\")"

        # Darwin policy sees `/tmp` and `/var` through their `/private` spelling.
        shared = "/tmp/wotex-lab-containment-#{System.unique_integer([:positive])}"
        File.mkdir!(shared)
        on_exit(fn -> File.rmdir(shared) end)

        assert {:ok, %{target: shared_config}} =
                 Containment.external_map(
                   context.probe,
                   ["{subject_archive}"],
                   context.archive,
                   shared,
                   launcher: context.launcher
                 )

        assert Enum.at(shared_config.args, 1) =~ "(subpath \"#{shared}\")"
        assert Enum.at(shared_config.args, 1) =~ "(subpath \"/private#{shared}\")"

      {true, {:unix, _}} ->
        assert {:ok, %{target: config}} = result
        assert ["--bind", directory, directory] in Enum.chunk_every(config.args, 3, 1, :discard)
        assert ["--dev", "/dev"] in Enum.chunk_every(config.args, 2, 1, :discard)
        assert config.environment["LC_ALL"] == "C.UTF-8"
        assert ["--proc", "/proc"] in Enum.chunk_every(config.args, 2, 1, :discard)

      _ ->
        assert {:error, %Error{code: :unsupported}} = result
    end
  end

  test "native launcher admission requires the exact operator-owned executable digest", context do
    admit = fn launcher ->
      Containment.external_map(context.probe, ["{subject_archive}"], context.archive, context.home,
        launcher: launcher
      )
    end

    assert {:error, %Error{code: :unsupported}} = admit.(nil)

    for launcher <- [
          "caller",
          %{},
          Map.put(context.launcher, :shell, true),
          %{context.launcher | executable: "relative"},
          %{context.launcher | executable: context.archive},
          %{context.launcher | digest: "missing"},
          %{context.launcher | digest: String.upcase(context.launcher.digest)}
        ] do
      assert {:error, %Error{code: :invalid_launcher}} = admit.(launcher)
    end

    wrong = %{context.launcher | digest: "sha256:" <> String.duplicate("0", 64)}
    assert {:error, %Error{code: :launcher_mismatch}} = admit.(wrong)

    link = Path.join(context.home, "launcher-link")
    File.ln_s!(context.launcher.executable, link)

    assert {:error, %Error{code: :invalid_launcher}} =
             admit.(%{context.launcher | executable: link})

    changed = Path.join(context.home, "changed-launcher")
    File.cp!(context.launcher.executable, changed)
    File.write!(changed, "changed", [:append])

    assert {:error, %Error{code: :launcher_mismatch}} =
             admit.(%{context.launcher | executable: changed})
  end

  defp sandbox_available? do
    case :os.type() do
      {:unix, :darwin} -> File.regular?("/usr/bin/sandbox-exec")
      {:unix, _} -> System.find_executable("bwrap") != nil
      _ -> false
    end
  end
end
