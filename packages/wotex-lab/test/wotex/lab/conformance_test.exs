defmodule Wotex.Lab.ConformanceTest do
  @moduledoc false

  use ExUnit.Case, async: true

  @moduletag :integration

  alias Wotex.Conformance.{Corpus, Report, Runner, Subject}
  alias Wotex.Conformance.Target.External
  alias Wotex.Lab.Conformance.Containment
  alias Wotex.Lab.Test.NativeContainment

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

    Map.merge(
      %{archive: archive, subject: subject, home: tmp},
      NativeContainment.build!()
    )
  end

  test "the core package passes both corpora as an external subject", context do
    for {corpus_dir, expected} <- [{"thing-description-1.1", 16}, {"thing-model-1.1", 8}] do
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

    [first | _] = corpus.vectors

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

  test "the host profile is path-free evidence for inherited resource and network limits",
       context do
    outside = Path.join(Path.dirname(context.home), "wotex-lab-outside-#{System.unique_integer()}")
    on_exit(fn -> File.rm(outside) end)

    assert {:ok, %{target: config, evidence: evidence}} =
             Containment.external_map(
               context.probe,
               ["probe", outside, "{subject_archive}"],
               context.archive,
               context.home,
               memory_bytes: 1_073_741_824,
               processes: 512,
               launcher: context.launcher
             )

    assert evidence["network"] == "denied"
    assert evidence["temporary_directory"] == "private"
    assert evidence["termination"] == "process_group"
    assert evidence["schema_version"] == "2.0.2"
    assert evidence["limits"]["memory_bytes"] == 1_073_741_824
    assert evidence["limits"]["wall_ms"] == 9_000
    assert evidence["limits"]["runner_timeout_ms"] == 10_000
    assert evidence["limits"]["runner_margin_ms"] == 1_000
    assert evidence["limits"]["cleanup_reserve_ms"] == 150
    refute inspect(evidence) =~ context.home
    refute inspect(evidence) =~ context.probe
    assert evidence["launcher"]["implementation"] == "rust-executable"
    assert evidence["launcher"]["version"] == "2.0.0"
    assert evidence["launcher"]["digest"] == context.launcher.digest

    assert {:ok, external} = External.from_map(config)

    request = %{
      "claim" => %{"operation" => "probe"},
      "vector" => %{"id" => "containment", "input" => %{}}
    }

    assert {:ok, response, _} = External.invoke(external, request)

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

    assert {:ok, %{target: config, evidence: evidence}} =
             Containment.external_map(
               context.probe,
               ["descendant", pid_file, "{subject_archive}"],
               context.archive,
               context.home,
               timeout_ms: 2_000,
               processes: 1_024,
               launcher: context.launcher
             )

    assert config.timeout_ms == 2_000
    assert evidence["limits"]["wall_ms"] == 1_000
    assert evidence["limits"]["runner_margin_ms"] == 1_000
    assert {:ok, external} = External.from_map(config)

    request = %{
      "claim" => %{"operation" => "probe"},
      "vector" => %{"id" => "descendant", "input" => %{}}
    }

    assert {:error, error, _} = External.invoke(external, request)
    assert error.code == :target_exit_nonzero
    assert File.regular?(pid_file)

    pid = pid_file |> File.read!() |> String.trim()
    assert eventually_stopped?(pid, 20)
  end

  test "CPU, memory and process ceilings terminate the target before the runner deadline",
       context do
    probes = [
      {"cpu", [cpu_seconds: 1, timeout_ms: 5_000]},
      {"memory", [memory_bytes: 33_554_432, timeout_ms: 5_000]},
      {"processes", [processes: 1, timeout_ms: 5_000]}
    ]

    for {id, limits} <- probes do
      assert {:ok, %{target: config}} =
               Containment.external_map(
                 context.probe,
                 [id, "{subject_archive}"],
                 context.archive,
                 context.home,
                 Keyword.put(limits, :launcher, context.launcher)
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

  test "repeated short-lived BEAM targets keep exec-transition accounting stable", context do
    {:ok, %{target: config}} = target_config(context, timeout_ms: 5_000)

    args =
      Enum.map(config.args, fn
        "{subject_archive}" -> context.archive
        argument -> argument
      end)

    {:ok, request} =
      Wotex.JSON.encode(%{
        "claim" => %{"operation" => "unsupported"},
        "vector" => %{"id" => "repeated", "input" => %{}}
      })

    for _ <- 1..30 do
      port =
        Port.open(
          {:spawn_executable, String.to_charlist(config.executable)},
          [
            :binary,
            :use_stdio,
            :exit_status,
            :stderr_to_stdout,
            args: args,
            env:
              Enum.map(config.environment, fn {key, value} ->
                {String.to_charlist(key), String.to_charlist(value)}
              end)
          ]
        )

      Port.command(port, request <> "\n")
      {status, text} = native_response(port, "")
      assert status == 0, "native supervisor failed (#{status}): #{text}"
      assert {:ok, %{"vector_id" => "repeated"}} = Wotex.JSON.decode(text)
    end
  end

  test "normal target exit also cleans up grouped and observed detached descendants", context do
    for mode <- ["normal-child", "escaped"] do
      pid_file = Path.join(context.home, mode <> ".pid")

      assert {:ok, %{target: config}} =
               Containment.external_map(
                 context.probe,
                 [mode, pid_file, "{subject_archive}"],
                 context.archive,
                 context.home,
                 launcher: context.launcher,
                 timeout_ms: 5_000
               )

      assert {:ok, external} = External.from_map(config)
      request = %{"claim" => %{"operation" => "probe"}, "vector" => %{"id" => mode, "input" => %{}}}
      assert {:ok, _, _} = External.invoke(external, request)
      assert eventually_stopped?(File.read!(pid_file), 40)
      refute Enum.any?(File.ls!(context.home), &String.starts_with?(&1, "run-"))
    end
  end

  test "contained protocol failures retain canonical runner error codes", context do
    probes = [
      {"malformed", :invalid_target_json},
      {"wrong-vector", :target_vector_mismatch},
      {"crash", :target_exit_nonzero},
      {"oversized", :target_exit_nonzero}
    ]

    for {id, expected_code} <- probes do
      assert {:ok, external} = contained_probe(context, id)

      request = %{
        "claim" => %{"operation" => "probe"},
        "vector" => %{"id" => id, "input" => %{}}
      }

      assert {:error, error, _} = External.invoke(external, request)
      assert error.code == expected_code
    end
  end

  test "concurrent contained runs cannot exchange filesystem state or response bytes", context do
    assert {:ok, external} = contained_probe(context, "concurrent")

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
      assert {:ok, response, _} = result
      assert response.vector_id == id
      assert response.actual == %{"marker" => id}
    end

    refute Enum.any?(File.ls!(context.home), &String.starts_with?(&1, "run-"))
  end

  defp target(context, options) do
    with {:ok, %{target: config}} <- target_config(context, options), do: External.from_map(config)
  end

  defp target_config(context, options) do
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

    Containment.external_map(
      erl,
      ["+JMsingle", "true", "+S", "1:1", "+A", "1", "-noshell"] ++
        paths ++ ["-eval", eval, "-extra", "--archive", "{subject_archive}"],
      context.archive,
      context.home,
      timeout_ms: Keyword.get(options, :timeout_ms, 10_000),
      launcher: context.launcher
    )
  end

  defp contained_probe(context, mode) do
    with {:ok, %{target: config}} <-
           Containment.external_map(
             context.probe,
             [mode, "{subject_archive}"],
             context.archive,
             context.home,
             timeout_ms: 5_000,
             launcher: context.launcher
           ) do
      External.from_map(config)
    end
  end

  defp native_response(port, text) do
    receive do
      {^port, {:data, bytes}} ->
        assert byte_size(text) + byte_size(bytes) <= 1_048_576
        native_response(port, text <> bytes)

      {^port, {:exit_status, status}} ->
        {status, text}
    after
      6_000 ->
        Port.close(port)
        flunk("native supervisor did not exit inside its outer deadline")
    end
  end

  defp eventually_stopped?(_, 0), do: false

  defp eventually_stopped?(pid, attempts) do
    if process_alive?(pid) do
      Process.sleep(25)
      eventually_stopped?(pid, attempts - 1)
    else
      true
    end
  end

  defp process_alive?(identity) do
    case String.split(identity, "@", parts: 2) do
      [pid] ->
        match?({_output, 0}, System.cmd("kill", ["-0", pid], stderr_to_stdout: true))

      [_, namespace] ->
        true = File.dir?("/proc")
        # A PID inside Bubblewrap is not a PID in the test runner's namespace.
        # Observe disappearance of that exact owned namespace, never signal or
        # accidentally inspect a same-numbered unrelated host process.
        "/proc/[0-9]*/ns/pid"
        |> Path.wildcard()
        |> Enum.any?(&(File.read_link(&1) == {:ok, namespace}))
    end
  end
end
