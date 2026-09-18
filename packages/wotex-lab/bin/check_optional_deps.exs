# Exercises Lab as a consumer without any optional dependency sees it (WLB.08:
# every module behind an optional seam is compiled only when its package is
# loaded). The `optional_deps` gate step compiles Lab into its own build path
# without the optional dependencies, with warnings as errors, and then runs
# this file in that build:
#
#     MIX_ENV=docs MIX_BUILD_PATH="$PWD/_build/no_optional_deps" mix do \
#       compile --no-optional-deps --warnings-as-errors + \
#       run --no-compile --no-deps-check bin/check_optional_deps.exs
#
# In any other build the optional dependencies are present and it fails.

ExUnit.start(autorun: false)

defmodule Wotex.Lab.Check.OptionalDepsTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab
  alias Wotex.Lab.Error
  alias Wotex.Lab.MCP.Server
  alias Wotex.Lab.Metrics.ReqSink
  alias Wotex.Lab.Otlp.GreptimeSink

  @token "optional-deps-write-token-0123456789"

  # Every Lab module compiled only when an optional package is loaded.
  @guarded [
    Wotex.Lab.Adapters.Directory.Authorization,
    Wotex.Lab.Adapters.Directory.Clock,
    Wotex.Lab.Adapters.Directory.EtsRepository,
    Wotex.Lab.Adapters.Directory.Identifier,
    Wotex.Lab.Adapters.Directory.SqliteRepository,
    Wotex.Lab.Adapters.HTTP.ReqClient,
    Wotex.Lab.Adapters.HTTP.SSE.Parser,
    Wotex.Lab.Adapters.HTTP.SSE.Session,
    Wotex.Lab.Adapters.MQTT.EmqttClient,
    Wotex.Lab.Adapters.MQTT.Session,
    Wotex.Lab.Adapters.Runtime.Loopback,
    Wotex.Lab.Adapters.Runtime.NoSec,
    Wotex.Lab.Adapters.Runtime.StaticRef,
    Wotex.Lab.Analytics,
    Wotex.Lab.Continuum.Channel,
    Wotex.Lab.Continuum.Host,
    Wotex.Lab.Continuum.Wire,
    Wotex.Lab.Experiments.RoomModel,
    Wotex.Lab.Formal.Profile,
    Wotex.Lab.MCP.Plug,
    Wotex.Lab.Reference.Thing,
    Wotex.Lab.SmartRoom.Scenario
  ]

  test "no optional dependency and no module behind its seam is loaded" do
    optional =
      for dependency <- Mix.Project.config()[:deps],
          opts = elem(dependency, tuple_size(dependency) - 1),
          Keyword.keyword?(opts) and opts[:optional],
          do: elem(dependency, 0)

    assert :req in optional and :plug in optional and :wotex_runtime in optional

    for app <- optional do
      assert :code.lib_dir(app) == {:error, :bad_name}, "#{app} is on the code path"
    end

    for module <- @guarded do
      refute Code.ensure_loaded?(module), "#{inspect(module)} was compiled"
    end
  end

  test "the remote-write sink admits the request, then reports the absent client" do
    request = %{body: "x", headers: [{"content-type", "application/x-protobuf"}]}

    assert {:error, %Error{code: :client_unavailable, phase: :export}} =
             ReqSink.write(request, {:bearer, "token"}, %{url: "http://127.0.0.1:9/write"})

    assert {:error, %Error{code: :invalid_sink_config}} = ReqSink.write(request, nil, %{})

    assert {:error, %Error{code: :unsupported_credential}} =
             ReqSink.write(request, {:token, "x"}, %{url: "http://127.0.0.1:9/write"})
  end

  test "the OTLP sink passes the absent client on" do
    assert {:ok, sink} = GreptimeSink.new(%{url: "http://127.0.0.1:9/v1/otlp"})

    assert {:error, %Error{code: :client_unavailable}} =
             sink.(:traces, %{body: "x", headers: []})
  end

  test "MCP authorizes writes and answers without the runtime and formal profiles" do
    lab = start_supervised!({Lab, id: "optional-deps", max_children: 1})

    formal = [
      pool: :optional_deps_formal,
      binary: "/nonexistent/maude",
      binary_digest: "sha256:" <> String.duplicate("0", 64)
    ]

    state = session(instance: lab, writes: true, write_token: @token, formal: formal)
    tools = request(state, "tools/list", %{})["result"]["tools"]
    assert "invoke_action" in Enum.map(tools, & &1["name"])

    assert %{"things" => [], "instance" => "explicit"} =
             tool(state, "list_things", %{})["result"]["structuredContent"]

    assert %{"code" => -32_601, "message" => "the runtime profile is not part of this host"} =
             tool(state, "read_property", %{"thing_id" => "urn:x", "property" => "p"})["error"]

    invoke = %{
      "thing_id" => "urn:x",
      "action" => "a",
      "authorization" => "wrong",
      "idempotency_key" => "k-1"
    }

    assert %{"code" => -32_001, "message" => "authorization refused"} =
             tool(state, "invoke_action", invoke)["error"]

    assert %{"code" => -32_601, "message" => "the runtime profile is not part of this host"} =
             tool(state, "invoke_action", %{invoke | "authorization" => @token})["error"]

    verify = tool(state, "verify_control_model", %{"variant" => "safe", "property" => "p"})

    assert %{"status" => "unsupported", "reason" => "the formal profile is not part of this host"} =
             verify["result"]["structuredContent"]

    assert %{"code" => -32_002} =
             request(state, "resources/read", %{"uri" => "wotex-lab://things/urn:x"})["error"]
  end

  defp session(opts) do
    {:ok, state} = Server.new(opts)

    {%{"result" => _}, state} =
      Server.handle(state, message("initialize", %{"protocolVersion" => "2025-11-25"}))

    {nil, state} =
      Server.handle(state, %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

    state
  end

  defp tool(state, name, arguments),
    do: request(state, "tools/call", %{"name" => name, "arguments" => arguments})

  defp request(state, method, params) do
    {reply, _} = Server.handle(state, message(method, params))
    reply
  end

  defp message(method, params),
    do: %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params}
end

case ExUnit.run() do
  %{failures: 0, total: total} when total > 0 -> :ok
  _ -> System.halt(1)
end
