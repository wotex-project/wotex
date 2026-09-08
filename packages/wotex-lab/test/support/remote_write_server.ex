defmodule Wotex.Lab.Test.RemoteWriteServer do
  @moduledoc false

  # A disposable Bandit/Plug remote-write endpoint. Each request pops the next
  # scripted reply (`{:status, code}`, `{:status, code, headers}` or `:hang`)
  # and records the decoded body, so a test can assert retries, drops, header
  # discipline and credential handling against real sockets.

  use Plug.Router

  alias Wotex.Lab.Test.RemoteWriteDecoder

  plug(:match)
  plug(:dispatch)

  @spec start([term()]) :: %{server: pid(), controller: pid(), port: pos_integer(), url: String.t()}
  def start(script) do
    {:ok, controller} = Agent.start_link(fn -> %{script: script, requests: []} end)

    {:ok, server} =
      Bandit.start_link(
        plug: {__MODULE__, controller},
        ip: {127, 0, 0, 1},
        port: 0,
        startup_log: false
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    url = "http://127.0.0.1:#{port}/v1/prometheus/write"
    %{server: server, controller: controller, port: port, url: url}
  end

  @spec requests(pid()) :: [map()]
  def requests(controller), do: controller |> Agent.get(& &1.requests) |> Enum.reverse()

  @spec await_requests(pid(), pos_integer(), pos_integer()) :: [map()]
  def await_requests(controller, count, attempts \\ 200) do
    case requests(controller) do
      requests when length(requests) >= count -> requests
      _fewer when attempts == 0 -> raise "expected #{count} remote-write requests"
      _fewer -> Process.sleep(10) && await_requests(controller, count, attempts - 1)
    end
  end

  @impl Plug
  def init(controller), do: controller

  @impl Plug
  def call(conn, controller), do: conn |> assign(:controller, controller) |> super(controller)

  post "/v1/prometheus/write" do
    controller = conn.assigns.controller
    {:ok, body, conn} = read_body(conn)

    reply =
      Agent.get_and_update(controller, fn state ->
        {reply, script} =
          case state.script do
            [] -> {{:status, 204}, []}
            [reply | rest] -> {reply, rest}
          end

        request = %{
          headers: conn.req_headers,
          authorization: get_req_header(conn, "authorization"),
          timeseries: RemoteWriteDecoder.decode_body(body),
          bytes: byte_size(body)
        }

        {reply, %{state | script: script, requests: [request | state.requests]}}
      end)

    case reply do
      {:status, status} ->
        send_resp(conn, status, "")

      {:status, status, headers} ->
        headers
        |> Enum.reduce(conn, fn {k, v}, c -> put_resp_header(c, k, v) end)
        |> send_resp(status, "")

      :hang ->
        Process.sleep(2_000)
        send_resp(conn, 204, "")
    end
  end

  match _ do
    send_resp(conn, 404, "")
  end
end
