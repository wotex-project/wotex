defmodule Wotex.Lab.Test.Greptime do
  @moduledoc false

  # A disposable greptime/greptimedb:v1.1.4 standalone container for the
  # metrics lane. It binds an ephemeral loopback port for the HTTP API only,
  # keeps no volume, has a 2 CPU / 1 GiB / 256 PID budget, and is removed in
  # `on_exit`. `read/4` is the bounded read
  # template used to verify ingestion: a fixed SELECT over one metric table
  # with validated identifiers, never caller-supplied SQL. `sql/2` is the
  # retention provisioning executor for statements that
  # `Wotex.Lab.Metrics.Retention` generates, and `flush/2` is the fixed
  # `ADMIN flush_table` template for the metric engine's physical table.
  # `otlp_rows/3` and `table_ttl/3` are fixed reads of the default OTLP trace
  # and log tables and of a table's TTL option.

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
    _ =
      System.cmd("docker", ["rm", "--force", "--volumes", container], stderr_to_stdout: true)

    :ok
  end

  @spec sql(t(), String.t()) :: {:ok, map()} | {:error, term()}
  def sql(greptime, statement) when is_binary(statement) do
    case Req.post(greptime.base_url <> "/v1/sql?db=public",
           form: [sql: statement],
           retry: false,
           receive_timeout: 10_000
         ) do
      {:ok, %{body: body}} when is_map(body) -> {:ok, body}
      {:ok, response} -> {:error, {:unexpected_status, response.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec otlp_rows(t(), :traces | :logs, String.t()) :: [list()]
  def otlp_rows(greptime, signal, database) do
    true = Regex.match?(@identifier, database)

    sql =
      case signal do
        :traces ->
          ~s(SELECT span_name, service_name, span_status_code, "span_attributes.wotex.lab.outcome_class" ) <>
            "FROM opentelemetry_traces ORDER BY span_name ASC LIMIT 100"

        :logs ->
          "SELECT severity_text, body, log_attributes FROM opentelemetry_logs ORDER BY timestamp ASC LIMIT 100"
      end

    response =
      Req.post!(greptime.base_url <> "/v1/sql?db=" <> database,
        form: [sql: sql],
        retry: false,
        receive_timeout: 10_000
      )

    case response.body do
      %{"output" => [%{"records" => %{"rows" => rows}}]} -> rows
      _ -> []
    end
  end

  @spec table_ttl(t(), String.t(), String.t()) :: String.t() | nil
  def table_ttl(greptime, table, database) do
    true = Regex.match?(@identifier, table) and Regex.match?(@identifier, database)

    response =
      Req.post!(greptime.base_url <> "/v1/sql?db=" <> database,
        form: [sql: ~s(SHOW CREATE TABLE "#{table}")],
        retry: false,
        receive_timeout: 10_000
      )

    with %{"output" => [%{"records" => %{"rows" => [[_, create]]}}]} <- response.body,
         [_, ttl] <- Regex.run(~r/ttl = '([^']+)'/, create) do
      ttl
    else
      _ -> nil
    end
  end

  @spec flush(t(), String.t()) :: :ok
  def flush(greptime, database) do
    true = Regex.match?(@identifier, database)

    response =
      Req.post!(greptime.base_url <> "/v1/sql?db=" <> database,
        form: [sql: "ADMIN flush_table('greptime_physical_table')"],
        retry: false,
        receive_timeout: 10_000
      )

    200 = response.status
    :ok
  end

  @spec read(t(), String.t(), [{String.t(), String.t()}], String.t()) :: [
          %{timestamp: integer(), value: number()}
        ]
  def read(greptime, metric, labels, database \\ "public") do
    true = Regex.match?(@identifier, metric) and Regex.match?(@identifier, database)

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
      Req.post!(greptime.base_url <> "/v1/sql?db=" <> database,
        form: [sql: sql],
        retry: false,
        receive_timeout: 10_000
      )

    rows =
      case {response.status, response.body} do
        {200, %{"output" => [%{"records" => %{"rows" => rows}}]}} when is_list(rows) ->
          rows

        other ->
          raise "GreptimeDB query failed: #{inspect(other, limit: 10, printable_limit: 1_024)}"
      end

    Enum.map(rows, fn [timestamp, value] -> %{timestamp: timestamp, value: value} end)
  end

  @spec await_rows(t(), String.t(), [{String.t(), String.t()}], pos_integer(), pos_integer()) ::
          [map()]
  def await_rows(greptime, metric, labels, count, attempts \\ 100) do
    case read(greptime, metric, labels) do
      rows when length(rows) >= count ->
        rows

      fewer when attempts == 0 ->
        raise "GreptimeDB expected #{count} rows for #{metric}, got #{inspect(fewer, limit: 10)}"

      _ ->
        Process.sleep(100)
        await_rows(greptime, metric, labels, count, attempts - 1)
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
          [mapping | _] -> mapping |> String.split(":") |> List.last() |> String.to_integer()
        end

      {_, _} ->
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

      _ ->
        Process.sleep(100)
        await_health(base_url, attempts - 1)
    end
  end
end
