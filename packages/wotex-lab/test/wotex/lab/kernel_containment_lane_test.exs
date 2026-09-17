defmodule Wotex.Lab.KernelContainmentLaneTest do
  @moduledoc false

  # Runs only with WOTEX_LAB_CONTAINER=1, an OCI runtime command on PATH and the
  # pinned image already present locally; the profile never pulls an image.
  #
  # The runner deadline is the profile's fixed 15-second budget, not a measured
  # bound: it exists to stop a hostile target, and container start dominates it
  # on a loaded machine. `timed/2` prints the wall time of each contained case
  # as `kernel-lane <name>_ms=<value>`; the WLB.06 record keeps the observed
  # values so a slow lane is read as machine load, never as a new limit.

  use ExUnit.Case, async: false

  @moduletag :container
  @moduletag timeout: 300_000

  alias Wotex.Conformance.{Corpus, Report, Runner, Subject}
  alias Wotex.Conformance.Target.External
  alias Wotex.Lab.Conformance.KernelContainment

  @image "hexpm/elixir@sha256:5858ed10da646c8d82a049d2c8c23ccb29c4ecedeb04e96414be3253609689da"
  @erl "/usr/local/lib/erlang/bin/erl"
  @beam ["+JMsingle", "true", "+S", "1:1", "+SDcpu", "1:1", "+SDio", "1", "+A", "1", "-noshell"]
  @generated_at ~U[2026-09-07 12:00:00Z]

  setup_all do
    executable = System.find_executable("docker") || flunk("the container lane needs docker")

    tmp =
      Path.join(
        System.tmp_dir!(),
        "wotex-lab-kernel-lane-" <> Base.encode16(:crypto.strong_rand_bytes(8))
      )

    home = Path.join(tmp, "home")
    File.mkdir_p!(home)
    on_exit(fn -> File.rm_rf!(tmp) end)
    archive = Path.join(tmp, "core-ebin.tar")

    :ok =
      :erl_tar.create(
        String.to_charlist(archive),
        [{~c"ebin", String.to_charlist(Application.app_dir(:wotex, "ebin"))}],
        [:compressed]
      )

    resolved = resolve(executable)
    digest = "sha256:" <> Base.encode16(:crypto.hash(:sha256, File.read!(resolved)), case: :lower)

    paths =
      Enum.map(
        [:elixir, :wotex, :jason, :ex_json_schema, :wotex_lab, :wotex_runtime, :nx, :telemetry],
        &Path.expand(Application.app_dir(&1, "ebin"))
      )

    %{
      runtime: %{executable: executable, digest: digest, image: @image},
      archive: archive,
      home: home,
      tmp: tmp,
      paths: paths,
      mounts: paths |> Enum.map(&(&1 |> Path.dirname() |> Path.dirname())) |> Enum.uniq()
    }
  end

  test "both core corpora pass through the kernel-isolated profile", context do
    digest =
      "sha256:" <> Base.encode16(:crypto.hash(:sha256, File.read!(context.archive)), case: :lower)

    {:ok, subject} =
      Subject.from_map(%{
        "id" => "wotex.core",
        "version" => to_string(Application.spec(:wotex, :vsn)),
        "artifact_digest" => digest,
        "interface" => %{"kind" => "lab_target", "revision" => "1"}
      })

    eval =
      "application:ensure_all_started(elixir), " <>
        "'Elixir.Wotex.Lab.Conformance.Target':main([unicode:characters_to_binary(A) || A <- init:get_plain_arguments()])"

    command =
      [@erl | @beam] ++
        ["-pa" | context.paths] ++ ["-eval", eval, "-extra", "--archive", "{subject_archive}"]

    assert {:ok, %{target: config, evidence: evidence, label: label}} =
             KernelContainment.external_map(
               context.runtime,
               command,
               context.archive,
               context.mounts,
               context.home
             )

    assert evidence["mechanism"] == "oci-linux-namespaces-cgroup-v2"
    assert {:ok, target} = External.from_map(config)

    for {corpus_dir, expected} <- [{"thing-description-1.1", 16}, {"thing-model-1.1", 8}] do
      {:ok, corpus} =
        Corpus.load(Application.app_dir(:wotex_conformance, "priv/vectors/" <> corpus_dir))

      assert {:ok, %Report{} = report} =
               timed("corpora_" <> corpus_dir, fn ->
                 Runner.run(corpus, subject, target, generated_at: @generated_at, environment: %{})
               end)

      assert Enum.reject(report.results, &(&1.status == :pass)) == []
      assert report.summary["pass"] == expected
    end

    assert :ok = release(context, label)
  end

  test "network, host files, writes and privileges are isolated", context do
    canary = Path.join(context.tmp, "host-canary")
    File.write!(canary, "host secret")
    mount = hd(context.mounts)

    code = """
    [Canary, Mount, _] = init:get_plain_arguments(),
    {ok, Nets} = file:list_dir("/sys/class/net"),
    Connect = case gen_tcp:connect({1,1,1,1}, 53, [], 1000) of {ok, _} -> connected; {error, _} -> denied end,
    Read = case file:read_file(Canary) of {ok, _} -> visible; {error, _} -> hidden end,
    Etc = element(1, file:write_file("/etc/wotex-lab-probe", <<"x">>)),
    Host = case file:write_file(filename:join(Mount, "wotex-lab-probe"), <<"x">>) of ok -> ok; {error, R} -> R end,
    Tmp = file:write_file("/tmp/wotex-lab-probe", <<"x">>),
    {ok, Status} = file:read_file("/proc/self/status"),
    Keep = [L || L <- binary:split(Status, <<"\\n">>, [global]),
                 lists:any(fun(P) -> binary:match(L, P) =:= {0, byte_size(P)} end,
                           [<<"Uid:">>, <<"CapEff:">>, <<"NoNewPrivs:">>])],
    io:format("~p.~n", [{lists:sort(Nets), Connect, Read, Etc, Host, Tmp, Keep}]),
    halt(0).
    """

    assert {0, output, label} =
             timed("isolation", fn -> probe(context, code, [canary, mount], []) end)

    assert {:ok, tokens, _} = output |> String.to_charlist() |> :erl_scan.string()
    assert {:ok, {nets, connect, read, etc, host, tmp, status}} = :erl_parse.parse_term(tokens)
    assert nets == [~c"lo"]
    assert connect == :denied
    assert read == :hidden
    assert etc == :error
    assert host == :erofs
    assert tmp == :ok

    assert Enum.map(status, &String.replace(&1, ~r/\s+/, " ")) == [
             "Uid: 65534 65534 65534 65534",
             "CapEff: 0000000000000000",
             "NoNewPrivs: 1"
           ]

    refute File.exists?(Path.join(mount, "wotex-lab-probe"))
    assert :ok = release(context, label)
  end

  test "kernel memory and process ceilings stop hostile targets", context do
    memory = """
    F = fun G(Acc) -> G([binary:copy(<<1>>, 1048576) | Acc]) end, F([]).
    """

    started = System.monotonic_time(:millisecond)

    assert {137, _, memory_label} =
             probe(context, memory, [], memory_bytes: 134_217_728, timeout_ms: 20_000)

    assert System.monotonic_time(:millisecond) - started < 20_000

    processes = """
    Spawn = fun S(N) -> try open_port({spawn_executable, "/bin/sleep"}, [{args, ["30"]}]) of _ -> S(N + 1) catch error:Reason -> {N, Reason} end end,
    {ok, Max} = file:read_file("/sys/fs/cgroup/pids.max"),
    io:format("~p.~n", [{Spawn(0), string:trim(binary_to_list(Max))}]),
    halt(0).
    """

    assert {0, output, process_label} = probe(context, processes, [], processes: 32)
    assert {:ok, tokens, _} = output |> String.to_charlist() |> :erl_scan.string()
    assert {:ok, {{spawned, reason}, ~c"32"}} = :erl_parse.parse_term(tokens)
    assert spawned in 1..31
    assert reason in [:eagain, :system_limit, :emfile]

    assert :ok = release(context, memory_label)
    assert :ok = release(context, process_label)
  end

  test "detached and hanging descendants end with the container", context do
    escape = """
    open_port({spawn_executable, "/usr/bin/setsid"}, [{args, ["/bin/sleep", "600"]}]),
    io:format("detached~n"),
    halt(0).
    """

    assert {0, "detached\n", escape_label} = probe(context, escape, [], [])
    assert eventually_empty?(context, escape_label)

    hang = """
    open_port({spawn_executable, "/usr/bin/setsid"}, [{args, ["/bin/sleep", "600"]}]),
    timer:sleep(infinity).
    """

    started = System.monotonic_time(:millisecond)
    assert {137, "", hang_label} = probe(context, hang, [], timeout_ms: 5_000)
    elapsed = System.monotonic_time(:millisecond) - started
    assert elapsed >= 2_000 and elapsed < 5_000
    assert eventually_empty?(context, hang_label)
  end

  test "concurrent contained targets cannot exchange output", context do
    code = """
    [Token, _] = init:get_plain_arguments(),
    timer:sleep(200),
    io:format("~s~n", [Token]),
    halt(0).
    """

    tasks =
      for token <- ["alpha", "beta", "gamma"] do
        Task.async(fn ->
          {token, timed("concurrent_" <> token, fn -> probe(context, code, [token], []) end)}
        end)
      end

    results = timed("concurrent_total", fn -> Task.await_many(tasks, 60_000) end)

    for {token, {0, output, label}} <- results do
      assert output == token <> "\n"
      assert :ok = release(context, label)
    end
  end

  # A contained case records its wall time instead of tightening the profile
  # budget; the deadline that bounds a hostile target is separate evidence.
  defp timed(name, fun) do
    started = System.monotonic_time(:millisecond)
    result = fun.()
    IO.puts("kernel-lane #{name}_ms=#{System.monotonic_time(:millisecond) - started}")
    result
  end

  defp probe(context, code, extra, opts) do
    command = [@erl | @beam] ++ ["-eval", code, "-extra"] ++ extra ++ ["{subject_archive}"]

    {:ok, %{target: target, label: label}} =
      KernelContainment.external_map(
        context.runtime,
        command,
        context.archive,
        context.mounts,
        context.home,
        opts
      )

    args = Enum.map(target.args, &if(&1 == "{subject_archive}", do: context.archive, else: &1))

    env =
      Enum.map(target.environment, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    port =
      Port.open({:spawn_executable, target.executable}, [
        :binary,
        :exit_status,
        args: args,
        env: env
      ])

    Port.command(port, "\n")
    {status, output} = collect(port, "", System.monotonic_time(:millisecond) + target.timeout_ms)
    {status, output, label}
  end

  defp collect(port, output, deadline) do
    receive do
      {^port, {:data, bytes}} when byte_size(output) + byte_size(bytes) <= 1_048_576 ->
        collect(port, output <> bytes, deadline)

      {^port, {:exit_status, status}} ->
        {status, output}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        Port.close(port)
        flunk("contained target outlived its runner deadline")
    end
  end

  defp release(context, label) do
    KernelContainment.release(context.runtime.executable, label, temporary_directory: context.home)
  end

  defp eventually_empty?(context, label, attempts \\ 60) do
    case KernelContainment.residue(context.runtime.executable, label,
           temporary_directory: context.home
         ) do
      {:ok, 0} ->
        true

      {:ok, _} when attempts > 0 ->
        Process.sleep(50)
        eventually_empty?(context, label, attempts - 1)

      _ ->
        false
    end
  end

  defp resolve(path, depth \\ 8) do
    case File.lstat!(path) do
      %File.Stat{type: :symlink} when depth > 0 ->
        {:ok, target} = :file.read_link_all(path)
        resolve(Path.expand(to_string(target), Path.dirname(path)), depth - 1)

      %File.Stat{type: :regular} ->
        path
    end
  end
end
