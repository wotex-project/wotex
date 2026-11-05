defmodule Wotex.Lab.MCPHTTPSessionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.MCP.{Jobs, Server}
  alias Wotex.Lab.MCP.Plug, as: MCPPlug

  test "overlapping HTTP calls cannot reuse an unaccounted session quota" do
    config = config(jobs: self(), max_calls: 1)
    session = initialize(config)
    first = Task.async(fn -> status(config, session) end)
    assert_receive {:"$gen_call", first_from, {:status, _, "job"}}
    parent = self()

    second =
      Task.async(fn ->
        conn = status(config, session)
        send(parent, {:second_completed, conn})
        conn
      end)

    on_exit(fn ->
      for task <- [first, second], Process.alive?(task.pid), do: Process.exit(task.pid, :kill)
    end)

    # The first request remains inside the trusted port. Observe either the
    # forbidden second entry or the transport's immediate refusal.
    overlapping =
      receive do
        {:"$gen_call", from, {:status, _, "job"}} ->
          GenServer.reply(from, {:ok, %{"status" => "completed"}})
          Task.await(second)

        {:second_completed, conn} ->
          Task.await(second)
          conn
      after
        1_000 -> flunk("the overlapping request neither entered nor refused")
      end

    GenServer.reply(first_from, {:ok, %{"status" => "completed"}})
    assert Task.await(first).status == 200
    assert overlapping.status == 409
    assert post(config, session, "tools/call", tool()).resp_body =~ "call quota exhausted"
  end

  test "HTTP initialization gives each session an independent benchmark authority" do
    jobs =
      start_supervised!(
        {Jobs, workloads: %{"fixture" => %{run: fn -> :ok end, dimensions: %{queue: 1}}}}
      )

    config = config(jobs: jobs)
    first = initialize(config)
    second = initialize(config)

    started =
      post(config, first, "tools/call", %{
        "name" => "start_benchmark",
        "arguments" => %{"workload" => "fixture", "samples" => 1}
      })

    job = Jason.decode!(started.resp_body)["result"]["structuredContent"]["job_id"]
    assert is_binary(job)

    foreign =
      post(config, second, "tools/call", %{
        "name" => "benchmark_status",
        "arguments" => %{"job_id" => job}
      })

    assert Jason.decode!(foreign.resp_body)["result"]["structuredContent"]["error"] == "unknown_job"

    assert post(config, first, "tools/call", %{
             "name" => "benchmark_status",
             "arguments" => %{"job_id" => job}
           }).resp_body =~ job
  end

  test "DELETE during a request cannot resurrect the session" do
    config = config(jobs: self())
    session = initialize(config)
    request = Task.async(fn -> status(config, session) end)
    assert_receive {:"$gen_call", from, {:status, _, "job"}}

    assert Plug.Test.conn(:delete, "/mcp")
           |> Plug.Conn.put_req_header("mcp-session-id", session)
           |> MCPPlug.call(config)
           |> Map.fetch!(:status) == 204

    GenServer.reply(from, {:ok, %{"status" => "completed"}})
    Task.await(request)
    assert post(config, session, "ping", %{}).status == 404
  end

  defp config(options) do
    {:ok, server} = Server.new(options)
    MCPPlug.init(server: server, sessions: MCPPlug.sessions_table())
  end

  defp initialize(config) do
    conn = post(config, nil, "initialize", %{"protocolVersion" => Server.protocol_version()})
    [session] = Plug.Conn.get_resp_header(conn, "mcp-session-id")
    session
  end

  defp status(config, session), do: post(config, session, "tools/call", tool())

  defp tool, do: %{"name" => "benchmark_status", "arguments" => %{"job_id" => "job"}}

  defp post(config, session, method, params) do
    message = %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params}
    conn = Plug.Test.conn(:post, "/mcp", Jason.encode!(message))
    conn = if session, do: Plug.Conn.put_req_header(conn, "mcp-session-id", session), else: conn
    MCPPlug.call(conn, config)
  end
end
