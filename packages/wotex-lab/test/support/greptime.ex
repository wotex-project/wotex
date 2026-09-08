defmodule Wotex.Lab.Test.Greptime do
  @moduledoc false

  # A disposable greptime/greptimedb:v1.1.4 standalone container for the
  # metrics lane. It binds an ephemeral loopback port for the HTTP API only,
  # keeps no volume, has a 2 CPU / 1 GiB / 256 PID budget, and is removed in
  # `on_exit`. `read/3` is the bounded read
  # template used to verify ingestion: a fixed SELECT over one metric table
  # with validated identifiers, never caller-supplied SQL.

  @image "greptime/greptimedb:v1.1.4"
  @identifier ~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/
  @value ~r/\A[a-zA-Z0-9_.:+-]*\z/

  @type t :: %{
          container: String.t(),
          port: pos_integer(),
          base_url: String.t(),
          write_url: String.t()
        }

  @spec start() :: t()
  def start do
    container = run()
    ExUnit.Callbacks.on_exit(fn -> halt(container) end)
    port = mapped_port(container, 40)
    base_url = "http://127.0.0.1:#{port}"
    :ok = await_health(base_url, 200)

    %{
      container: container,
      port: port,
      base_url: base_url,
      write_url: base_url <> "/v1/prometheus/write?db=public"
    }
  end

  @spec halt(String.t()) :: :ok
  def halt(container) do
    _removed =
      System.cmd("docker", ["rm", "--force", "--volumes", container], stderr_to_stdout: true)

    :ok
  end

  @spec read(t(), String.t(), [{String.t(), String.t()}]) :: [
          %{timestamp: integer(), value: number()}
        ]
  def read(greptime, metric, labels) do
    true = Regex.match?(@identifier, metric)

    conditions =
      Enum.map(labels, fn {name, value} ->
        true = Regex.match?(@identifier, name) and Regex.match?(@value, value)
        ~s(#{name} = '#{value}')
      end)

    where = if conditions == [], do: "", else: " WHERE " <> Enum.join(conditions, " AND ")

    sql =
      ~s(SELECT greptime_timestamp, greptime_value FROM "#{metric}"#{where} ) <>
        "ORDER BY greptime_timestamp ASC LIMIT 100"

    response =
      Req.post!(greptime.base_url <> "/v1/sql?db=public",
        form: [sql: sql],
        retry: false,
        receive_timeout: 10_000
      )

    rows =
      case response.body do
        %{"output" => [%{"records" => %{"rows" => rows}}]} -> rows
        _other -> []
      end

    Enum.map(rows, fn [timestamp, value] -> %{timestamp: timestamp, value: value} end)
  end

  @spec await_rows(t(), String.t(), [{String.t(), String.t()}], pos_integer(), pos_integer()) ::
          [map()]
  def await_rows(greptime, metric, labels, count, attempts \\ 100) do
    case read(greptime, metric, labels) do
      rows when length(rows) >= count -> rows
      _fewer when attempts == 0 -> raise "GreptimeDB never returned #{count} rows for #{metric}"
      _fewer -> Process.sleep(100) && await_rows(greptime, metric, labels, count, attempts - 1)
    end
  end

  defp run do
    {output, 0} =
      System.cmd(
        "docker",
        [
          "run",
          "--detach",
          "--rm",
          "--cpus",
          "2",
          "--memory",
          "1g",
          "--memory-swap",
          "1g",
          "--pids-limit",
          "256",
          "--publish",
          "127.0.0.1::4000",
          @image
        ] ++
          ["standalone", "start", "--http-addr", "0.0.0.0:4000"],
        stderr_to_stdout: true
      )

    output |> String.trim() |> String.split("\n") |> List.last()
  end

  defp mapped_port(container, 0), do: raise("GreptimeDB #{container} published no mapped port")

  defp mapped_port(container, attempts) do
    case System.cmd("docker", ["port", container, "4000"], stderr_to_stdout: true) do
      {output, 0} ->
        case String.split(String.trim(output), "\n", trim: true) do
          [] -> retry_port(container, attempts)
          [mapping | _rest] -> mapping |> String.split(":") |> List.last() |> String.to_integer()
        end

      {_output, _status} ->
        retry_port(container, attempts)
    end
  end

  defp retry_port(container, attempts) do
    Process.sleep(100)
    mapped_port(container, attempts - 1)
  end

  defp await_health(base_url, 0), do: raise("GreptimeDB at #{base_url} never became healthy")

  defp await_health(base_url, attempts) do
    case Req.get(base_url <> "/health", retry: false, receive_timeout: 1_000) do
      {:ok, %{status: 200}} ->
        :ok

      _other ->
        Process.sleep(100)
        await_health(base_url, attempts - 1)
    end
  end
end
