defmodule Wotex.Lab.Test.HttpServer do
  @moduledoc false

  # A disposable Bandit/Plug server for the HTTP/SSE lane. The SSE endpoint is
  # scripted: the test pushes raw chunks and closes the stream explicitly.

  use Plug.Router

  plug(:match)
  plug(:dispatch)

  @token "room-token-7f3a"

  @spec start(pid(), keyword()) ::
          {:ok, %{server: pid(), controller: pid(), port: non_neg_integer()}}
  def start(test_pid, opts \\ []) do
    {:ok, controller} = Agent.start_link(fn -> %{test_pid: test_pid, stream: nil} end)

    bandit_options =
      [
        plug: {__MODULE__, controller},
        ip: {127, 0, 0, 1},
        port: 0,
        startup_log: false
      ] ++ Keyword.take(opts, [:scheme, :certfile, :keyfile])

    {:ok, server} =
      Bandit.start_link(bandit_options)

    {:ok, %{port: port}} = listener(server)
    {:ok, %{server: server, controller: controller, port: port}}
  end

  @spec push(pid(), binary()) :: :ok
  def push(controller, chunk) do
    send(stream_pid(controller), {:chunk, chunk})
    :ok
  end

  @spec close_stream(pid()) :: :ok
  def close_stream(controller) do
    send(stream_pid(controller), :close)
    :ok
  end

  @spec target(pid()) :: binary() | nil
  def target(controller), do: Agent.get(controller, &Map.get(&1, :target))

  @spec stream_pid(pid()) :: pid()
  def stream_pid(controller), do: wait_stream(controller, 200)

  defp wait_stream(_controller, 0), do: raise("no SSE stream connected")

  defp wait_stream(controller, attempts) do
    case Agent.get(controller, & &1.stream) do
      pid when is_pid(pid) ->
        pid

      nil ->
        Process.sleep(5)
        wait_stream(controller, attempts - 1)
    end
  end

  defp listener(server) do
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    {:ok, %{port: port}}
  end

  @impl Plug
  def init(controller), do: controller

  @impl Plug
  def call(conn, controller) do
    conn |> assign(:controller, controller) |> super(controller)
  end

  get "/properties/temperature" do
    json(conn, 200, "21.5")
  end

  get "/properties/large" do
    json(conn, 200, Jason.encode!(String.duplicate("x", 4_096)))
  end

  get "/properties/slow" do
    Process.sleep(400)
    json(conn, 200, "1")
  end

  get "/properties/redirect" do
    conn |> put_resp_header("location", "/properties/temperature") |> send_resp(302, "")
  end

  get "/properties/html" do
    conn |> put_resp_content_type("text/html") |> send_resp(200, "<b>21</b>")
  end

  put "/properties/target" do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> @token] ->
        {:ok, body, conn} = read_body(conn)
        Agent.update(conn.assigns.controller, &Map.put(&1, :target, body))
        send_resp(conn, 204, "")

      _other ->
        send_resp(conn, 401, "")
    end
  end

  post "/actions/set-target" do
    {:ok, body, conn} = read_body(conn)
    json(conn, 202, ~s({"status":"pending","input":#{body}}))
  end

  get "/properties/temperature/observe" do
    controller = conn.assigns.controller
    handler = self()
    Agent.update(controller, &Map.put(&1, :stream, handler))

    send(
      Agent.get(controller, & &1.test_pid),
      {:stream_opened, get_req_header(conn, "authorization")}
    )

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> send_chunked(200)

    stream_loop(conn, controller)
  end

  get "/properties/temperature/observe-wrong-type" do
    conn |> put_resp_content_type("application/json") |> send_resp(200, "[]")
  end

  match _ do
    send_resp(conn, 404, "")
  end

  defp stream_loop(conn, controller) do
    receive do
      {:chunk, data} ->
        case chunk(conn, data) do
          {:ok, conn} -> stream_loop(conn, controller)
          {:error, _reason} -> finish(conn, controller)
        end

      :close ->
        finish(conn, controller)
    after
      10_000 ->
        finish(conn, controller)
    end
  end

  defp finish(conn, controller) do
    Agent.update(controller, &Map.put(&1, :stream, nil))
    conn
  end

  defp json(conn, status, body) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, body)
  end
end
