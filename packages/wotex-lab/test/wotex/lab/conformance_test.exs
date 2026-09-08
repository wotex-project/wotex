defmodule Wotex.Lab.ConformanceTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Conformance.{Corpus, Report, Runner, Subject}
  alias Wotex.Conformance.Target.External
  alias Wotex.Lab.Conformance.{Containment, Target}

  @generated_at ~U[2026-09-07 12:00:00Z]

  setup_all do
    tmp =
      Path.join(System.tmp_dir!(), "wotex-lab-conformance-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    archive = Path.join(tmp, "core-ebin.tar")

    :ok =
      :erl_tar.create(
        String.to_charlist(archive),
        [{~c"ebin", String.to_charlist(Application.app_dir(:wotex, "ebin"))}],
        [:compressed]
      )

    digest = "sha256:" <> Base.encode16(:crypto.hash(:sha256, File.read!(archive)), case: :lower)

    {:ok, subject} =
      Subject.from_map(%{
        "id" => "wotex.core",
        "version" => to_string(Application.spec(:wotex, :vsn)),
        "artifact_digest" => digest,
        "interface" => %{"kind" => "lab_target", "revision" => "1"}
      })

    on_exit(fn -> File.rm_rf!(tmp) end)
    %{archive: archive, subject: subject, home: tmp}
  end

  test "the core package passes both corpora as an external subject", context do
    for {corpus_dir, expected} <- [{"thing-description-1.1", 14}, {"thing-model-1.1", 6}] do
      {:ok, corpus} =
        Corpus.load(Application.app_dir(:wotex_conformance, "priv/vectors/" <> corpus_dir))

      {:ok, target} = target(context, timeout_ms: 30_000)

      assert {:ok, %Report{} = report} =
               Runner.run(corpus, context.subject, target,
                 generated_at: @generated_at,
                 environment: %{"runtime" => "wotex_lab"}
               )

      failures = Enum.reject(report.results, &(&1.status == :pass))

      assert failures == [],
             "unexpected outcomes: " <>
               inspect(Enum.map(failures, &{&1.vector_id, &1.status, &1.code}))

      assert report.summary["pass"] == expected
      assert length(report.results) == expected
      assert {:ok, encoded} = Report.encode(report)
      refute encoded =~ "Minimal Thing"
    end
  end

  test "a changed archive is refused before any vector runs", context do
    {:ok, corpus} =
      Corpus.load(Application.app_dir(:wotex_conformance, "priv/vectors/thing-model-1.1"))

    {:ok, forged} =
      Subject.from_map(%{
        "id" => "wotex.core",
        "version" => "0.0.0",
        "artifact_digest" => "sha256:" <> String.duplicate("0", 64),
        "interface" => %{"kind" => "lab_target", "revision" => "1"}
      })

    {:ok, target} = target(context, timeout_ms: 30_000)

    assert {:ok, report} =
             Runner.run(corpus, forged, target, generated_at: @generated_at, environment: %{})

    assert report.summary["infrastructure_error"] == length(corpus.vectors)
  end

  test "a runner-owned changed expectation is a fail rather than a protocol error", context do
    {:ok, corpus} =
      Corpus.load(Application.app_dir(:wotex_conformance, "priv/vectors/thing-model-1.1"))

    [first | _rest] = corpus.vectors

    mismatched = %{
      first
      | expectation: %{first.expectation | digest: "sha256:" <> String.duplicate("0", 64)}
    }

    {:ok, external} = target(context, timeout_ms: 30_000)

    assert {:ok, report} =
             Runner.run(%{corpus | vectors: [mismatched]}, context.subject, external,
               generated_at: @generated_at,
               environment: %{}
             )

    assert [%{status: :fail, code: "exact_mismatch"}] = report.results
    assert report.summary["fail"] == 1
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
    python = "/usr/bin/python3"
    outside = Path.join(Path.dirname(context.home), "wotex-lab-outside-#{System.unique_integer()}")
    on_exit(fn -> File.rm(outside) end)

    probe = """
    import json, os, resource, socket, sys
    request = json.loads(sys.stdin.readline())
    try:
      candidate = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
      candidate.bind(("127.0.0.1", 0))
      network = "available"
    except OSError:
      network = "denied"
    try:
      with open(sys.argv[1], "w") as output:
        output.write("escaped")
      outside_write = "available"
    except OSError:
      outside_write = "denied"
    with open(os.path.join(os.environ["HOME"], "private-write"), "w") as output:
      output.write("admitted")
    print(json.dumps({
      "protocol": "wotex.conformance.target",
      "protocol_version": "1.0",
      "vector_id": request["vector"]["id"],
      "outcome": "observed",
      "actual": {
        "network": network,
        "outside_write": outside_write,
        "private_cwd": os.path.realpath(os.getcwd()) == os.path.realpath(os.environ["HOME"]),
        "private_write": os.path.isfile(os.path.join(os.environ["HOME"], "private-write")),
        "cpu_seconds": resource.getrlimit(resource.RLIMIT_CPU)[0],
        "open_files": resource.getrlimit(resource.RLIMIT_NOFILE)[0]
      },
      "codes": []
    }))
    """

    assert {:ok, %{target: config, evidence: evidence}} =
             Containment.external_map(
               python,
               ["-c", probe, outside, "{subject_archive}"],
               context.archive,
               context.home,
               memory_bytes: 1_073_741_824,
               processes: 512
             )

    assert evidence["network"] == "denied"
    assert evidence["temporary_directory"] == "private"
    assert evidence["termination"] == "process_group"
    assert evidence["limits"]["memory_bytes"] == 1_073_741_824
    refute inspect(evidence) =~ context.home
    refute inspect(evidence) =~ python

    assert {:ok, external} = External.from_map(config)

    request = %{
      "claim" => %{"operation" => "probe"},
      "vector" => %{"id" => "containment", "input" => %{}}
    }

    assert {:ok, response, _duration} = External.invoke(external, request)

    assert response.actual == %{
             "network" => "denied",
             "outside_write" => "denied",
             "private_cwd" => true,
             "private_write" => true,
             "cpu_seconds" => 8,
             "open_files" => 128
           }

    refute File.exists?(outside)
    refute File.exists?(Path.join(context.home, "private-write"))
    refute Enum.any?(File.ls!(context.home), &String.starts_with?(&1, "run-"))
  end

  test "the inner deadline reaps the complete target process group", context do
    pid_file = Path.join(context.home, "descendant.pid")

    probe = """
    import subprocess, sys, time
    child = subprocess.Popen(["/bin/sleep", "30"])
    with open(sys.argv[1], "w") as output:
      output.write(str(child.pid))
      output.flush()
    time.sleep(30)
    """

    assert {:ok, %{target: config}} =
             Containment.external_map(
               "/usr/bin/python3",
               ["-c", probe, pid_file, "{subject_archive}"],
               context.archive,
               context.home,
               timeout_ms: 500,
               processes: 1_024
             )

    assert {:ok, external} = External.from_map(config)

    request = %{
      "claim" => %{"operation" => "probe"},
      "vector" => %{"id" => "descendant", "input" => %{}}
    }

    assert {:error, error, _duration} = External.invoke(external, request)
    assert error.code == :target_exit_nonzero
    assert File.regular?(pid_file)

    pid = pid_file |> File.read!() |> String.trim()
    assert eventually_stopped?(pid, 20)
  end

  test "CPU, memory and process ceilings terminate the target before the runner deadline",
       context do
    probes = [
      {"cpu", "while True: pass", [cpu_seconds: 1, timeout_ms: 5_000]},
      {"memory", "import time; x = bytearray(64 * 1024 * 1024); time.sleep(30)",
       [memory_bytes: 33_554_432, timeout_ms: 5_000]},
      {"processes",
       "import subprocess, time; subprocess.Popen(['/bin/sleep', '30']); time.sleep(30)",
       [processes: 1, timeout_ms: 5_000]}
    ]

    for {id, probe, limits} <- probes do
      assert {:ok, %{target: config}} =
               Containment.external_map(
                 "/usr/bin/python3",
                 ["-c", probe, "{subject_archive}"],
                 context.archive,
                 context.home,
                 limits
               )

      assert {:ok, external} = External.from_map(config)

      request = %{
        "claim" => %{"operation" => "probe"},
        "vector" => %{"id" => id, "input" => %{}}
      }

      assert {:error, error, duration} = External.invoke(external, request)
      assert error.code == :target_exit_nonzero
      assert duration < 4_000_000
    end
  end

  test "invalid containment inputs are refused before a target starts", context do
    valid_args = ["{subject_archive}"]
    assert Containment.profile().version == "1.0.0"

    assert {:error, %Wotex.Lab.Error{code: :invalid_path}} =
             Containment.external_map("relative", valid_args, context.archive, context.home)

    assert {:error, %Wotex.Lab.Error{code: :invalid_path}} =
             Containment.external_map("mix.exs", valid_args, context.archive, context.home)

    assert {:error, %Wotex.Lab.Error{code: :invalid_path}} =
             Containment.external_map(context.archive, valid_args, context.archive, context.home)

    assert {:error, %Wotex.Lab.Error{code: :invalid_path}} =
             Containment.external_map("/usr/bin/python3", valid_args, 1, context.home)

    assert {:error, %Wotex.Lab.Error{code: :invalid_path}} =
             Containment.external_map(
               "/usr/bin/python3",
               valid_args,
               context.archive,
               "relative"
             )

    assert {:error, %Wotex.Lab.Error{code: :invalid_path}} =
             Containment.external_map(
               "/usr/bin/python3",
               valid_args,
               context.archive,
               Path.join(context.home, "missing")
             )

    unsafe = Path.join(context.home, "unsafe\"directory")
    File.mkdir!(unsafe)

    assert {:error, %Wotex.Lab.Error{code: :invalid_path}} =
             Containment.external_map("/usr/bin/python3", valid_args, context.archive, unsafe)

    assert {:error, %Wotex.Lab.Error{code: :invalid_arguments}} =
             Containment.external_map("/usr/bin/python3", [], context.archive, context.home)

    for args <- [
          [1, "{subject_archive}"],
          [String.duplicate("x", 4_097), "{subject_archive}"],
          ["{subject_archive}", "{subject_archive}"],
          List.duplicate("argument", 28) ++ ["{subject_archive}"]
        ] do
      assert {:error, %Wotex.Lab.Error{code: :invalid_arguments}} =
               Containment.external_map("/usr/bin/python3", args, context.archive, context.home)
    end

    assert {:error, %Wotex.Lab.Error{code: :invalid_arguments}} =
             Containment.external_map(
               "/usr/bin/python3",
               ["prefix-{subject_archive}"],
               context.archive,
               context.home
             )

    assert {:error, %Wotex.Lab.Error{code: :invalid_limit}} =
             Containment.external_map(
               "/usr/bin/python3",
               valid_args,
               context.archive,
               context.home,
               memory_bytes: 1
             )

    assert {:error, %Wotex.Lab.Error{code: :invalid_options}} =
             Containment.external_map(
               "/usr/bin/python3",
               valid_args,
               context.archive,
               context.home,
               shell: true
             )

    assert {:error, %Wotex.Lab.Error{code: :invalid_options}} =
             Containment.external_map(
               "/usr/bin/python3",
               valid_args,
               context.archive,
               context.home,
               [1]
             )

    assert {:error, %Wotex.Lab.Error{code: :invalid_options}} =
             Containment.external_map(
               "/usr/bin/python3",
               valid_args,
               context.archive,
               context.home,
               timeout_ms: 1_000,
               timeout_ms: 2_000
             )

    assert {:error, %Wotex.Lab.Error{code: :invalid_limit}} =
             Containment.external_map(
               "/usr/bin/python3",
               valid_args,
               context.archive,
               context.home,
               timeout_ms: 120_001
             )
  end

  test "a non-symlinked Darwin sandbox directory is represented directly", context do
    directory = Path.join(File.cwd!(), ".containment-#{System.unique_integer([:positive])}")
    File.mkdir!(directory)
    on_exit(fn -> File.rmdir(directory) end)

    assert {:ok, %{target: config}} =
             Containment.external_map(
               "/usr/bin/python3",
               ["{subject_archive}"],
               context.archive,
               directory
             )

    assert Enum.at(config.args, 1) =~ "(subpath \"#{directory}\")"
  end

  test "contained protocol failures retain canonical runner error codes", context do
    probes = [
      {"malformed", "print('{')", :invalid_target_json},
      {"wrong-vector",
       "import json, sys; request=json.loads(sys.stdin.readline()); print(json.dumps({'protocol':'wotex.conformance.target','protocol_version':'1.0','vector_id':'other','outcome':'unsupported','codes':['probe']}))",
       :target_vector_mismatch},
      {"crash", "import os; os._exit(42)", :target_exit_nonzero},
      {"oversized", "import sys; sys.stdout.write('x' * 2000000)", :target_exit_nonzero}
    ]

    for {id, probe, expected_code} <- probes do
      assert {:ok, external} = contained_python(context, probe)

      request = %{
        "claim" => %{"operation" => "probe"},
        "vector" => %{"id" => id, "input" => %{}}
      }

      assert {:error, error, _duration} = External.invoke(external, request)
      assert error.code == expected_code
    end
  end

  test "concurrent contained runs cannot exchange filesystem state or response bytes", context do
    probe = """
    import json, os, sys, time
    request = json.loads(sys.stdin.readline())
    identifier = request["vector"]["id"]
    marker = os.path.join(os.environ["HOME"], "marker")
    with open(marker, "w") as output:
      output.write(identifier)
    time.sleep(0.05)
    with open(marker) as source:
      observed = source.read()
    print(json.dumps({
      "protocol": "wotex.conformance.target",
      "protocol_version": "1.0",
      "vector_id": identifier,
      "outcome": "observed",
      "actual": {"marker": observed},
      "codes": []
    }))
    """

    assert {:ok, external} = contained_python(context, probe)

    results =
      1..12
      |> Task.async_stream(
        fn index ->
          id = "concurrent-#{index}"

          request = %{
            "claim" => %{"operation" => "probe"},
            "vector" => %{"id" => id, "input" => %{}}
          }

          {id, External.invoke(external, request)}
        end,
        max_concurrency: 12,
        ordered: false,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    for {id, result} <- results do
      assert {:ok, response, _duration} = result
      assert response.vector_id == id
      assert response.actual == %{"marker" => id}
    end

    refute Enum.any?(File.ls!(context.home), &String.starts_with?(&1, "run-"))
  end

  defp target(context, options) do
    erl = Path.join([to_string(:code.root_dir()), "bin", "erl"])

    paths =
      Enum.flat_map(
        [:elixir, :wotex, :jason, :ex_json_schema, :wotex_lab, :wotex_runtime, :nx, :telemetry],
        fn app ->
          ["-pa", Application.app_dir(app, "ebin")]
        end
      )

    eval =
      "application:ensure_all_started(elixir), " <>
        "'Elixir.Wotex.Lab.Conformance.Target':main([unicode:characters_to_binary(A) || A <- init:get_plain_arguments()])"

    with {:ok, %{target: config}} <-
           Containment.external_map(
             erl,
             ["+S", "1:1", "+A", "1", "+P", "1024", "-noshell"] ++
               paths ++ ["-eval", eval, "-extra", "--archive", "{subject_archive}"],
             context.archive,
             context.home,
             timeout_ms: Keyword.get(options, :timeout_ms, 10_000)
           ) do
      External.from_map(config)
    end
  end

  defp contained_python(context, code) do
    with {:ok, %{target: config}} <-
           Containment.external_map(
             "/usr/bin/python3",
             ["-c", code, "{subject_archive}"],
             context.archive,
             context.home,
             timeout_ms: 5_000
           ) do
      External.from_map(config)
    end
  end

  defp eventually_stopped?(_pid, 0), do: false

  defp eventually_stopped?(pid, attempts) do
    case System.cmd("kill", ["-0", pid], stderr_to_stdout: true) do
      {_output, 0} ->
        Process.sleep(25)
        eventually_stopped?(pid, attempts - 1)

      {_output, _status} ->
        true
    end
  end
end
