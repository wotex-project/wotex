defmodule Wotex.Workspace.BenchReport do
  @moduledoc """
  The Markdown reports of `mix native.bench`. A package's documentation
  includes every `bench/output/*.md`, so a native report sits beside the
  reports of its Elixir benchmarks. `render/1` writes:

      # <title>

      <description>

      ## System

      - Operating system: ...
      - CPU: ...
      - Compiler: ...

      ## Results

      <tables>

      <what the columns mean>

  The tables come from the benchmark tool: `nanobench_tables/1` keeps the
  Markdown tables a nanobench driver prints, and `criterion/1` reads the
  estimates `cargo bench` leaves in `CRITERION_HOME`, which
  `criterion_table/1` renders with the mean, median and standard deviation
  of the time per iteration and, where the benchmark declares one, the
  throughput at the mean.
  """

  @typedoc "Labelled lines of the System section, in order."
  @type system :: [{String.t(), String.t()}]

  @type report :: %{
          title: String.t(),
          description: String.t(),
          system: system(),
          results: String.t(),
          note: String.t() | nil
        }

  @typedoc """
  One criterion benchmark: its id and the point estimates, in nanoseconds,
  with the declared throughput (`benchmark.json`), if any.
  """
  @type estimate :: %{
          id: String.t(),
          mean: float(),
          median: float(),
          std_dev: float(),
          throughput: map() | nil
        }

  @nanobench_note "nanobench's columns: the time and the rate per unit, `err%` the median " <>
                    "absolute percentage error across epochs, and `total` the seconds the " <>
                    "benchmark ran. `:wavy_dash:` marks a result nanobench considers unstable."

  @criterion_note "Mean, median and standard deviation of the time per iteration are " <>
                    "criterion's bootstrap point estimates; throughput is the declared " <>
                    "throughput per mean iteration time."

  @doc "The column note of nanobench results."
  @spec nanobench_note() :: String.t()
  def nanobench_note, do: @nanobench_note

  @doc "The column note of criterion results."
  @spec criterion_note() :: String.t()
  def criterion_note, do: @criterion_note

  @doc "Renders a report."
  @spec render(report()) :: String.t()
  def render(report) do
    system =
      case report.system do
        [] ->
          []

        lines ->
          [
            "## System\n\n",
            Enum.map(lines, fn {label, value} -> "- #{label}: #{value}\n" end),
            "\n"
          ]
      end

    note = if report.note, do: ["\n", report.note, "\n"], else: []

    IO.iodata_to_binary([
      ["# ", report.title, "\n\n"],
      [String.trim(report.description), "\n\n"],
      system,
      ["## Results\n\n", String.trim(report.results), "\n"],
      note
    ])
  end

  @doc """
  The Markdown tables in nanobench's output (runs of lines starting with
  `|`), joined by blank lines. nanobench leaves the last cell of a row open;
  each row is closed with ` |`, which ExDoc's Markdown parser needs to see
  a table. Warnings and other output are left out.
  """
  @spec nanobench_tables(String.t()) :: String.t()
  def nanobench_tables(output) do
    output
    |> String.split(["\r\n", "\n"])
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.chunk_by(&String.starts_with?(&1, "|"))
    |> Enum.filter(fn [line | _] -> String.starts_with?(line, "|") end)
    |> Enum.map_join("\n\n", fn rows -> Enum.map_join(rows, "\n", &close_row/1) end)
  end

  defp close_row(row) do
    if String.ends_with?(row, "|") and not String.ends_with?(row, "\\|"),
      do: row,
      else: row <> " |"
  end

  @doc """
  Reads every benchmark criterion recorded below `home` (its
  `CRITERION_HOME`): the `new/benchmark.json` and `new/estimates.json` of
  each, sorted by id.
  """
  @spec criterion(Path.t()) :: {:ok, [estimate()]} | {:error, String.t()}
  def criterion(home) do
    home
    |> Path.join("**/new/benchmark.json")
    |> Path.wildcard()
    |> Enum.reduce_while({:ok, []}, fn benchmark, {:ok, acc} ->
      estimates = Path.join(Path.dirname(benchmark), "estimates.json")

      with {:ok, benchmark_json} <- read_json(benchmark),
           {:ok, estimates_json} <- read_json(estimates),
           {:ok, estimate} <- estimate(benchmark_json, estimates_json) do
        {:cont, {:ok, [estimate | acc]}}
      else
        {:error, message} -> {:halt, {:error, "#{Path.relative_to(benchmark, home)}: #{message}"}}
      end
    end)
    |> then(fn
      {:ok, estimates} -> {:ok, Enum.sort_by(estimates, & &1.id)}
      error -> error
    end)
  end

  @doc """
  One estimate from criterion's `benchmark.json` and `estimates.json`
  (decoded).
  """
  @spec estimate(map(), map()) :: {:ok, estimate()} | {:error, String.t()}
  def estimate(%{"full_id" => id} = benchmark, %{} = estimates) when is_binary(id) do
    with {:ok, mean} <- point(estimates, "mean"),
         {:ok, median} <- point(estimates, "median"),
         {:ok, std_dev} <- point(estimates, "std_dev") do
      {:ok,
       %{
         id: id,
         mean: mean,
         median: median,
         std_dev: std_dev,
         throughput: benchmark["throughput"]
       }}
    end
  end

  def estimate(_, _), do: {:error, "not a criterion benchmark record"}

  defp point(estimates, key) do
    case estimates[key] do
      %{"point_estimate" => value} when is_number(value) -> {:ok, value / 1}
      _ -> {:error, "no #{key} point estimate"}
    end
  end

  @doc """
  A Markdown table of criterion estimates: benchmark, mean, median, standard
  deviation and, when any estimate declares one, throughput.
  """
  @spec criterion_table([estimate()]) :: String.t()
  def criterion_table(estimates) do
    throughput? = Enum.any?(estimates, &(throughput(&1.throughput, &1.mean) != nil))

    header =
      ["Benchmark", "Mean", "Median", "Std. dev."] ++ if(throughput?, do: ["Throughput"], else: [])

    align = [":--", "--:", "--:", "--:"] ++ if(throughput?, do: ["--:"], else: [])

    rows =
      for estimate <- estimates do
        cells = [
          "`#{String.replace(estimate.id, "|", "\\|")}`",
          duration(estimate.mean),
          duration(estimate.median),
          duration(estimate.std_dev)
        ]

        cells ++
          if(throughput?, do: [throughput(estimate.throughput, estimate.mean) || "-"], else: [])
      end

    Enum.map_join([header, align | rows], "\n", &("| " <> Enum.join(&1, " | ") <> " |"))
  end

  @doc "Formats nanoseconds with four significant digits in ns, µs, ms or s."
  @spec duration(number()) :: String.t()
  def duration(ns) when ns < 1.0e3, do: significant(ns) <> " ns"
  def duration(ns) when ns < 1.0e6, do: significant(ns / 1.0e3) <> " µs"
  def duration(ns) when ns < 1.0e9, do: significant(ns / 1.0e6) <> " ms"
  def duration(ns), do: significant(ns / 1.0e9) <> " s"

  @doc """
  The rate a criterion throughput declaration (`{"Bytes" => n}`,
  `{"BytesDecimal" => n}`, `{"Elements" => n}` or `{"ElementsAndBytes" =>
  %{"elements" => e, "bytes" => b}}`) reaches at `mean_ns` per iteration,
  scaled as criterion prints it (binary for bytes, decimal otherwise), or
  `nil`.
  """
  @spec throughput(map() | nil, number()) :: String.t() | nil
  def throughput(_, mean_ns) when mean_ns <= 0, do: nil
  def throughput(%{"Bytes" => bytes}, mean_ns) when is_number(bytes), do: bytes_rate(bytes, mean_ns)

  def throughput(%{"BytesDecimal" => bytes}, mean_ns) when is_number(bytes),
    do: rate(bytes, mean_ns, 1000, ~w(B/s KB/s MB/s GB/s TB/s))

  def throughput(%{"Elements" => elements}, mean_ns) when is_number(elements),
    do: elements_rate(elements, mean_ns)

  def throughput(%{"ElementsAndBytes" => %{"elements" => elements, "bytes" => bytes}}, mean_ns)
      when is_number(elements) and is_number(bytes),
      do: elements_rate(elements, mean_ns) <> ", " <> bytes_rate(bytes, mean_ns)

  def throughput(_, _), do: nil

  defp bytes_rate(bytes, mean_ns), do: rate(bytes, mean_ns, 1024, ~w(B/s KiB/s MiB/s GiB/s TiB/s))

  defp elements_rate(elements, mean_ns),
    do: rate(elements, mean_ns, 1000, ~w(elem/s Kelem/s Melem/s Gelem/s Telem/s))

  defp rate(amount, mean_ns, base, [unit | larger]) do
    scale(amount * 1.0e9 / mean_ns, base, unit, larger)
  end

  defp scale(value, base, _, [next | larger]) when value >= base,
    do: scale(value / base, base, next, larger)

  defp scale(value, _, unit, _), do: significant(value) <> " " <> unit

  defp significant(value) when value >= 100, do: :erlang.float_to_binary(value / 1, decimals: 1)
  defp significant(value) when value >= 10, do: :erlang.float_to_binary(value / 1, decimals: 2)
  defp significant(value), do: :erlang.float_to_binary(value / 1, decimals: 3)

  defp read_json(path) do
    with {:ok, text} <- File.read(path),
         {:ok, json} <- JSON.decode(text) do
      {:ok, json}
    else
      {:error, reason} when is_atom(reason) -> {:error, :file.format_error(reason) |> to_string()}
      {:error, _} -> {:error, "invalid JSON"}
    end
  end
end
