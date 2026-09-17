defmodule WotexLabWorkbench.FakeGreptime do
  @moduledoc false

  # A scripted loopback HTTP peer for provisioning and exporter tests. Every
  # request is reported to the owning test process with its method, path,
  # query string, headers and body; the test chooses the reply through
  # `{:reply, status, body}` messages or the default JSON answers below. The
  # owner travels as a tagged tuple because plug options admit no bare PID.

  @behaviour Plug

  import Plug.Conn

  @doc false
  @spec start(pid()) :: {pid(), pos_integer()}
  def start(owner) do
    {:ok, server} =
      Bandit.start_link(
        plug: {__MODULE__, {:owner, owner}},
        scheme: :http,
        ip: {127, 0, 0, 1},
        port: 0,
        startup_log: false
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    {server, port}
  end

  @impl Plug
  def init({:owner, owner}), do: {:owner, owner}

  @impl Plug
  def call(conn, {:owner, owner}) do
    {:ok, body, conn} = read_body(conn, length: 1_048_576)

    send(
      owner,
      {:fake_greptime, self(),
       %{
         method: conn.method,
         path: conn.request_path,
         query: conn.query_string,
         headers: conn.req_headers,
         body: body
       }}
    )

    {status, reply} =
      receive do
        {:reply, status, reply} -> {status, reply}
      after
        2_000 -> {500, "{}"}
      end

    conn |> put_resp_content_type("application/json") |> send_resp(status, reply)
  end
end
