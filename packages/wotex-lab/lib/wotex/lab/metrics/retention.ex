defmodule Wotex.Lab.Metrics.Retention do
  @moduledoc """
  Closed retention provisioning for a GreptimeDB durable metric database.

  WLB.10 sets the default durable metric TTL to seven days and lets an explicit
  operator profile override it. `plan/1` admits that choice: a lowercase
  database identifier that is not `public`, `information_schema` or
  `greptime_private`, and a TTL of whole hours or days from `1h` to `3650d`
  (`"7d"` by default). The plan carries the TTL text and its exact seconds.

  `statements/1` returns the two fixed DDL templates, `CREATE DATABASE IF NOT
  EXISTS ... WITH (ttl = ...)` followed by `ALTER DATABASE ... SET 'ttl' = ...`,
  so a second provisioning run also changes an existing database.
  `verification/1` reads the database options from `information_schema`.
  `provision/2` runs the statements and the verification through a
  host-supplied executor and compares the effective TTL, which GreptimeDB
  normalizes into units such as `2months 29days 2h 52m 48s`, by exact seconds.
  The executor receives only these generated statements and returns the
  decoded JSON body of GreptimeDB's HTTP SQL API (`/v1/sql`), or an error.

  Provisioning is an operator action with its own credential scope. This
  module performs no network access, accepts no caller SQL and never returns
  the executor's error text. GreptimeDB 1.1.4 enforces TTL per stored file: a
  flushed file whose newest row is older than the TTL is removed, while rows
  still in memory or sharing a file with newer rows remain queryable until a
  later flush or compaction. Retention therefore bounds storage; it is not a
  query-time filter. Run evidence records are stored outside GreptimeDB and do
  not expire with metric TTL.

  ## Examples

      iex> {:ok, plan} = Wotex.Lab.Metrics.Retention.plan(database: "wotex_lab")
      iex> {plan.ttl, plan.seconds}
      {"7d", 604800}
      iex> Wotex.Lab.Metrics.Retention.statements(plan)
      ["CREATE DATABASE IF NOT EXISTS wotex_lab WITH (ttl = '7d')",
       "ALTER DATABASE wotex_lab SET 'ttl' = '7d'"]
  """

  alias Wotex.Lab.{Error, Options}

  @default_ttl "7d"
  @database ~r/\A[a-z][a-z0-9_]{0,62}\z/
  @reserved ~w(public information_schema greptime_private)
  @ttl ~r/\A([1-9][0-9]{0,5})([hd])\z/
  @min_seconds 3_600
  @max_seconds 3_650 * 86_400
  @units %{
    "years" => 31_557_600,
    "year" => 31_557_600,
    "months" => 2_630_016,
    "month" => 2_630_016,
    "weeks" => 604_800,
    "week" => 604_800,
    "days" => 86_400,
    "day" => 86_400,
    "h" => 3_600,
    "m" => 60,
    "s" => 1
  }

  @enforce_keys [:database, :ttl, :seconds]
  defstruct [:database, :ttl, :seconds]

  @typedoc "An admitted retention plan."
  @type t :: %__MODULE__{database: String.t(), ttl: String.t(), seconds: pos_integer()}

  @typedoc "Runs one generated SQL statement and returns GreptimeDB's decoded JSON body."
  @type executor :: (String.t() -> {:ok, map()} | {:error, term()})

  @doc "The default durable metric TTL."
  @spec default_ttl() :: String.t()
  def default_ttl, do: @default_ttl

  @doc "Admits `:database` and an optional `:ttl` into a retention plan."
  @spec plan(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def plan(opts) do
    with :ok <- Options.validate(opts, [:database, :ttl]),
         {:ok, database} <- database(Keyword.get(opts, :database)),
         {:ok, seconds} <- ttl_seconds(Keyword.get(opts, :ttl, @default_ttl)) do
      {:ok,
       %__MODULE__{database: database, ttl: Keyword.get(opts, :ttl, @default_ttl), seconds: seconds}}
    else
      {:error, %Error{code: :invalid_options}} -> invalid("retention options are invalid")
      {:error, %Error{}} = error -> error
    end
  end

  @doc "Admits a durable metric database identifier."
  @spec database(term()) :: {:ok, String.t()} | {:error, Error.t()}
  def database(name) when is_binary(name) do
    if Regex.match?(@database, name) and name not in @reserved,
      do: {:ok, name},
      else: invalid("database must be a non-reserved lowercase identifier")
  end

  def database(_), do: invalid("database must be a non-reserved lowercase identifier")

  @doc "The fixed DDL statements that create the database and apply its TTL."
  @spec statements(t()) :: [String.t()]
  def statements(%__MODULE__{database: database, ttl: ttl}) do
    [
      "CREATE DATABASE IF NOT EXISTS #{database} WITH (ttl = '#{ttl}')",
      "ALTER DATABASE #{database} SET 'ttl' = '#{ttl}'"
    ]
  end

  @doc "The fixed read that returns the database options."
  @spec verification(t()) :: String.t()
  def verification(%__MODULE__{database: database}),
    do: "SELECT options FROM information_schema.schemata WHERE schema_name = '#{database}'"

  @doc "Parses a GreptimeDB humantime TTL, such as `7days` or `2h 30m`, into seconds."
  @spec seconds(term()) :: {:ok, pos_integer()} | {:error, Error.t()}
  def seconds(text) when is_binary(text) and byte_size(text) in 1..128 do
    text
    |> String.split(" ", trim: true)
    |> Enum.reduce_while({:ok, 0}, fn part, {:ok, total} ->
      with [_, count, unit] <- Regex.run(~r/\A([0-9]{1,6})([a-z]+)\z/, part),
           {:ok, factor} <- Map.fetch(@units, unit) do
        {:cont, {:ok, total + String.to_integer(count) * factor}}
      else
        _ -> {:halt, unverified()}
      end
    end)
    |> case do
      {:ok, total} when total > 0 -> {:ok, total}
      _ -> unverified()
    end
  end

  def seconds(_), do: unverified()

  @doc """
  Runs the statements and verification through `executor` and checks the TTL.

  Returns the database, TTL text and effective seconds. A refused statement is
  `retention_refused`, an executor failure `retention_unavailable`, a missing or
  unparseable option `retention_unverified` and a different effective TTL
  `retention_not_applied`.
  """
  @spec provision(t(), executor()) :: {:ok, map()} | {:error, Error.t()}
  def provision(%__MODULE__{} = plan, executor) when is_function(executor, 1) do
    with :ok <- run_statements(plan, executor),
         {:ok, body} <- execute(executor, verification(plan), 3),
         {:ok, effective} <- effective(body) do
      if effective == plan.seconds do
        {:ok, %{database: plan.database, ttl: plan.ttl, seconds: effective}}
      else
        {:error,
         Error.new(:retention_not_applied, :retention, "effective TTL differs from the plan",
           details: %{expected_seconds: plan.seconds, effective_seconds: effective}
         )}
      end
    end
  end

  defp run_statements(plan, executor) do
    plan
    |> statements()
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {statement, step}, :ok ->
      case execute(executor, statement, step) do
        {:ok, %{"output" => [%{"affectedrows" => rows}]}} when is_integer(rows) -> {:cont, :ok}
        {:ok, _} -> {:halt, refused(step)}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp execute(executor, statement, step) do
    case executor.(statement) do
      {:ok, %{"code" => code}} when is_integer(code) ->
        refused(step, code)

      {:ok, body} when is_map(body) ->
        {:ok, body}

      _ ->
        {:error,
         Error.new(:retention_unavailable, :retention, "the database did not answer",
           details: %{step: step},
           class: :unavailable
         )}
    end
  end

  defp effective(%{"output" => [%{"records" => %{"rows" => [[options]]}}]})
       when is_binary(options) do
    case Regex.run(~r/'ttl'='([^']{1,128})'/, options) do
      [_, ttl] -> seconds(ttl)
      nil -> unverified()
    end
  end

  defp effective(_), do: unverified()

  defp ttl_seconds(ttl) when is_binary(ttl) do
    with [_, count, unit] <- Regex.run(@ttl, ttl),
         seconds = String.to_integer(count) * if(unit == "h", do: 3_600, else: 86_400),
         true <- seconds >= @min_seconds and seconds <= @max_seconds do
      {:ok, seconds}
    else
      _ -> invalid("ttl must be whole hours or days from 1h to 3650d")
    end
  end

  defp ttl_seconds(_), do: invalid("ttl must be whole hours or days from 1h to 3650d")

  defp refused(step, code \\ nil) do
    {:error,
     Error.new(:retention_refused, :retention, "the database refused a retention statement",
       details: %{step: step, code: code}
     )}
  end

  defp unverified,
    do:
      {:error,
       Error.new(:retention_unverified, :retention, "the effective TTL could not be verified")}

  defp invalid(message), do: {:error, Error.new(:invalid_retention, :construction, message)}
end
