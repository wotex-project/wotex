defmodule WotexLabWorkbench.Health do
  @moduledoc """
  Minimal liveness/readiness checks for the optional host and OCI runtime.

  The HTTP status exposes no process identifiers, counters or configuration.
  `probe/1` is a dependency-free loopback probe for an image health check; it
  sends one fixed request, accepts only an HTTP 200 status line and closes the
  socket. Neither operation opens a browser session or starts optional work.
  """

  @required [
    WotexLabWorkbench.Supervisor,
    WotexLabWorkbench.Lab,
    WotexLabWorkbench.Metrics,
    WotexLabWorkbench.Sessions,
    WotexLabWorkbenchWeb.Endpoint
  ]

  @doc "Returns `:ok` only when every required host process is alive."
  @spec status([atom()]) :: :ok | {:error, :unavailable}
  def status(required \\ @required) when is_list(required) do
    if required != [] and Enum.all?(required, &alive?/1), do: :ok, else: {:error, :unavailable}
  end

  @doc "Performs one fixed loopback HTTP health probe for release containers."
  @spec probe(pos_integer()) :: :ok | {:error, :unavailable}
  def probe(port \\ configured_port())

  def probe(port) when is_integer(port) and port in 1..65_535 do
    options = [:binary, active: false, packet: :line, packet_size: 256]

    case :gen_tcp.connect(~c"127.0.0.1", port, options, 1_000) do
      {:ok, socket} ->
        result = request(socket)
        :gen_tcp.close(socket)
        result

      _unavailable ->
        {:error, :unavailable}
    end
  end

  def probe(_port), do: {:error, :unavailable}

  defp configured_port do
    case Integer.parse(System.get_env("PORT") || "4000") do
      {port, ""} -> port
      _invalid -> 0
    end
  end

  defp request(socket) do
    with :ok <-
           :gen_tcp.send(
             socket,
             "GET /healthz HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
           ),
         {:ok, response} <- :gen_tcp.recv(socket, 0, 1_000),
         true <- String.starts_with?(response, "HTTP/1.1 200") do
      :ok
    else
      _unavailable -> {:error, :unavailable}
    end
  end

  defp alive?(name), do: name |> Process.whereis() |> then(&(is_pid(&1) and Process.alive?(&1)))
end
