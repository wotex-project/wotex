defmodule WotexLabWorkbenchWeb.HealthControllerTest do
  @moduledoc false

  use WotexLabWorkbenchWeb.ConnCase, async: false

  alias WotexLabWorkbench.Health

  test "health route is data-free, non-cacheable and does not create a session", %{conn: conn} do
    before_sessions = WotexLabWorkbench.Sessions.count()
    response = get(conn, "/healthz")

    assert json_response(response, 200) == %{"schema_version" => "1.0.0", "status" => "ok"}
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert WotexLabWorkbench.Sessions.count() == before_sessions
    assert get_resp_header(response, "set-cookie") == []
  end

  test "readiness refuses empty, unknown and dead process cohorts" do
    assert Health.status([]) == {:error, :unavailable}
    assert Health.status([__MODULE__.Missing]) == {:error, :unavailable}

    name = Module.concat(__MODULE__, Probe)
    pid = spawn(fn -> Process.sleep(:infinity) end)
    Process.register(pid, name)
    assert Health.status([name]) == :ok
    Process.exit(pid, :kill)
    assert eventually(fn -> Health.status([name]) == {:error, :unavailable} end)
  end

  test "the release probe admits only a bounded port" do
    assert Health.probe(0) == {:error, :unavailable}
    assert Health.probe(65_536) == {:error, :unavailable}
  end

  test "the release probe accepts only an HTTP 200 status line" do
    {port, server} =
      health_server("HTTP/1.1 200 OK\r\ncontent-length: 0\r\nconnection: close\r\n\r\n")

    assert Health.probe(port) == :ok
    Task.await(server)

    {port, server} =
      health_server(
        "HTTP/1.1 503 Service Unavailable\r\ncontent-length: 0\r\nconnection: close\r\n\r\n"
      )

    assert Health.probe(port) == {:error, :unavailable}
    Task.await(server)
  end

  test "the release probe reads its default port from bounded runtime configuration" do
    previous = System.get_env("PORT")
    on_exit(fn -> restore_port(previous) end)

    {port, server} =
      health_server("HTTP/1.1 200 OK\r\ncontent-length: 0\r\nconnection: close\r\n\r\n")

    System.put_env("PORT", Integer.to_string(port))
    assert Health.probe() == :ok
    Task.await(server)

    System.put_env("PORT", "not-a-port")
    assert Health.probe() == {:error, :unavailable}
  end

  defp eventually(fun, attempts \\ 20)
  defp eventually(fun, 0), do: fun.()
  defp eventually(fun, attempts), do: fun.() || (Process.sleep(5) && eventually(fun, attempts - 1))

  defp health_server(response) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(listener)

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        {:ok, _request} = :gen_tcp.recv(socket, 0, 1_000)
        :ok = :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
      end)

    {port, server}
  end

  defp restore_port(nil), do: System.delete_env("PORT")
  defp restore_port(value), do: System.put_env("PORT", value)
end
