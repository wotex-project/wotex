# Run only against an explicitly built, locally available image ID. No image
# is pulled, and every container and anonymous volume belongs to this check.
Code.require_file("support/oci_runtime.exs", __DIR__)
Code.require_file("support/child_environment.exs", __DIR__)

{:ok, options} = Wotex.Lab.Check.OCIRuntime.parse(System.argv())
File.mkdir!(options.output)
File.chmod!(options.output, 0o700)
ExUnit.start(autorun: false)

defmodule Wotex.Lab.Check.OCIRuntimeTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Check.{ChildEnvironment, OCIRuntime}

  @release "/opt/wotex/bin/wotex_lab_workbench"
  @moduletag timeout: 120_000

  setup_all do
    {:ok, options} = OCIRuntime.parse(System.argv())
    image = inspect_object("image", options.image)
    assert image["Id"] == options.image
    assert image["Os"] == "linux"
    assert image["Config"]["User"] == "65532:65532"
    name = "wotex-lab-oci-" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
    on_exit(fn -> cleanup(name, options, image) end)
    secret = Base.encode64(:crypto.strong_rand_bytes(64))

    docker!(OCIRuntime.arguments(options.image, name), [{"SECRET_KEY_BASE", secret}])
    container = inspect_object("container", name)
    assert OCIRuntime.runtime_policy?(container, options.image)
    binding = docker!(["port", name, "4000/tcp"]) |> String.trim()
    assert [_, port] = Regex.run(~r/\A127\.0\.0\.1:(\d+)\z/, binding)
    base = "http://127.0.0.1:#{port}"
    {:ok, _} = Application.ensure_all_started(:inets)

    assert ready?(base, System.monotonic_time(:millisecond) + 20_000),
           "container did not become healthy within twenty seconds"

    %{name: name, base: base}
  end

  test "health and documentation/search load without allocating a session", context do
    assert String.trim(rpc(context.name, "IO.puts(WotexLabWorkbench.Sessions.count())")) == "0"
    assert {:ok, {{_, 200, _}, _, _}} = request(context.base <> "/healthz")
    assert {:ok, {{_, 200, _}, _, body}} = request(context.base <> "/docs/start/")
    assert body =~ "id=\"doc-main\""
    assert body =~ "Search documentation"

    path =
      context.name
      |> rpc(
        ~S|{:ok, site} = WotexLabWorkbench.Documentation.site(); IO.puts(site.metadata["search_contract"]["path"])|
      )
      |> String.trim()

    assert String.starts_with?(path, "/") and not String.starts_with?(path, "//")
    assert {:ok, {{_, 200, _}, _, javascript}} = request(context.base <> path)
    assert byte_size(javascript) > 1_000
    assert String.trim(rpc(context.name, "IO.puts(WotexLabWorkbench.Sessions.count())")) == "0"
  end

  test "the release executes a run, capture and explicit approval, refusing replay", context do
    script = ~S'''
    alias WotexLabWorkbench.{Sessions, Room, Experiments, Report}
    {:ok, session} = Sessions.open()
    nil = session.room
    {:ok, session} = Sessions.admit(session.token, :run)
    try do
      3 = length(Room.things(session.room))
      [] = Room.runs(session.room)
      {:ok, thermal} = Experiments.fetch("thermal")
      {:ok, params} = Experiments.admit(thermal, %{})
      {:ok, run} = Room.start_run(session.room, thermal.id, params)
      :completed = run.status
      {:ok, capture} = Room.export_dataset(session.room, limit: 100)
      true = capture.rows > 0
      {:ok, json} = session.room |> Room.snapshot() |> Report.build() |> Report.encode()
      true = byte_size(json) > 100
      {:ok, smart} = Experiments.fetch("smart_room")
      {:ok, params} = Experiments.admit(smart, %{})
      {:ok, run} = Room.start_run(session.room, smart.id, params)
      :awaiting_approval = run.status
      nil = run.effect
      decision = run.decision
      approval = %{"decision_id" => decision["id"], "proposal_digest" => decision["proposal_digest"],
        "revision" => to_string(decision["state_revision"]), "expires_at" => to_string(decision["expires_at"])}
      {:ok, dispatched} = Room.approve(session.room, run.id, approval)
      :dispatched = dispatched.status
      true = dispatched.effect == dispatched.proposal["input"]
      {:error, _} = Room.approve(session.room, run.id, approval)
    after
      :ok = Sessions.revoke(session.token)
    end
    false = Process.alive?(session.room)
    IO.puts("run/capture/approval/replay/cleanup: passed")
    '''

    assert rpc(context.name, script) =~ "run/capture/approval/replay/cleanup: passed"
  end

  test "the image health command and non-root runtime identity pass", context do
    assert docker!(["exec", context.name, "id", "-u"]) == "65532\n"

    docker!([
      "exec",
      context.name,
      "timeout",
      "30",
      @release,
      "eval",
      "case WotexLabWorkbench.Health.probe() do :ok -> :ok; _ -> System.halt(1) end"
    ])

    for path <- ["/api/v1/scenarios", "/api/v1/metrics/catalogue"],
        do: assert({:ok, {{_, 200, _}, _, _}} = request(context.base <> path))
  end

  test "all Workbench pages serve their local executable assets", context do
    session =
      context.name
      |> rpc(~S'''
      alias WotexLabWorkbenchWeb.{Endpoint, Plugs.SessionToken}
      {:ok, session} = WotexLabWorkbench.Sessions.open()
      options = Endpoint.session_options()
      conn = %Plug.Conn{secret_key_base: Endpoint.config(:secret_key_base)}
      cookie = Plug.Session.COOKIE.put(conn, nil, %{SessionToken.key() => session.token}, Plug.Session.COOKIE.init(options))
      IO.puts(Jason.encode!(%{token: session.token, cookie: Keyword.fetch!(options, :key) <> "=" <> cookie}))
      ''')
      |> JSON.decode!()

    try do
      for path <- ["/", "/things", "/experiments", "/metrics", "/evidence"] do
        assert {:ok, {{_, 200, _}, _, body}} =
                 request(context.base <> path, [{~c"cookie", String.to_charlist(session["cookie"])}])

        scripts = Regex.scan(~r/<script[^>]+src="(\/[^"]+)"/, body, capture: :all_but_first)
        assert scripts != []

        for [script] <- scripts do
          refute String.starts_with?(script, "//")
          assert {:ok, {{_, 200, _}, _, bytes}} = request(context.base <> script)
          assert byte_size(bytes) > 100
        end
      end
    after
      rpc(context.name, "WotexLabWorkbench.Sessions.revoke(#{inspect(session["token"])})")
    end

    assert String.trim(rpc(context.name, "IO.puts(WotexLabWorkbench.Sessions.count())")) == "0"
  end

  defp docker!(arguments, environment \\ []) do
    case System.cmd("docker", arguments,
           env: environment ++ ChildEnvironment.scrubbed(),
           stderr_to_stdout: true
         ) do
      {output, 0} -> output
      {output, status} -> flunk("docker #{hd(arguments)} failed (#{status}): #{output}")
    end
  end

  defp inspect_object(kind, identity) do
    [kind, "inspect", "--format", "{{json .}}", identity]
    |> docker!()
    |> JSON.decode!()
  end

  defp rpc(name, script), do: docker!(["exec", name, "timeout", "30", @release, "rpc", script])

  defp request(url, headers \\ [], timeout \\ 3_000) do
    :httpc.request(
      :get,
      {String.to_charlist(url), headers},
      [timeout: timeout, connect_timeout: min(timeout, 1_000)],
      body_format: :binary
    )
  end

  defp ready?(base, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0 do
      case request(base <> "/healthz", [], min(remaining, 1_000)) do
        {:ok, {{_, 200, _}, _, _}} ->
          true

        _ ->
          Process.sleep(min(200, max(deadline - System.monotonic_time(:millisecond), 0)))
          ready?(base, deadline)
      end
    else
      false
    end
  end

  defp cleanup(name, options, image) do
    listing = ["container", "ls", "--all", "--quiet", "--filter", "name=^/#{name}$"]

    if String.trim(docker!(listing)) != "" do
      try do
        File.write!(Path.join(options.output, "container.log"), docker!(["logs", name]))
        docker!(["stop", "--time", "15", name])
        state = inspect_object("container", name)["State"]
        assert state["ExitCode"] == 0
        assert state["OOMKilled"] == false

        File.write!(
          Path.join(options.output, "runtime.json"),
          JSON.encode!(%{
            image: options.image,
            os: image["Os"],
            architecture: image["Architecture"],
            labels: image["Config"]["Labels"],
            exit_code: state["ExitCode"],
            oom_killed: state["OOMKilled"]
          })
        )
      after
        docker!(["rm", "--force", "--volumes", name])
        assert String.trim(docker!(listing)) == ""
      end
    end
  end
end

result = ExUnit.run()
File.write!(Path.join(options.output, "tests.json"), JSON.encode!(result))
System.halt(if result.failures == 0, do: 0, else: 1)
