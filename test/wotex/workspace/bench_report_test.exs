defmodule Wotex.Workspace.BenchReportTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.BenchReport
  alias WotexWorkspace.Fixtures

  # Output of a nanobench driver: a warning block and two tables, whose rows
  # nanobench leaves open on the right.
  @nanobench_output """

  Warning, results might be unstable:
  * CPU frequency scaling enabled: CPU 0 between 800.0 and 4,000.0 MHz

  |               ns/op |                op/s |    err% |     total | queue
  |--------------------:|--------------------:|--------:|----------:|:------
  |               18.29 |       54,662,954.29 |    1.0% |      0.06 | `admit`
  |              394.15 |        2,537,086.94 |    0.7% |      0.06 | :wavy_dash: `flush`

  |             ns/byte |              byte/s |    err% |     total | benchmark
  |--------------------:|--------------------:|--------:|----------:|:----------
  |                0.25 |    4,000,000,000.00 |    0.1% |      0.01 | `copy`
  """

  # criterion 0.7 records, as `cargo bench` writes them below CRITERION_HOME.
  @estimates %{
    "mean" => %{
      "confidence_interval" => %{
        "confidence_level" => 0.95,
        "lower_bound" => 3.45,
        "upper_bound" => 3.53
      },
      "point_estimate" => 3.4875162480536197,
      "standard_error" => 0.019
    },
    "median" => %{"point_estimate" => 3.4738318847947616, "standard_error" => 0.017},
    "median_abs_dev" => %{"point_estimate" => 0.0325, "standard_error" => 0.028},
    "slope" => %{"point_estimate" => 3.4856, "standard_error" => 0.018},
    "std_dev" => %{"point_estimate" => 0.06318442831300931, "standard_error" => 0.015}
  }

  defp write_criterion(home, directory, benchmark, estimates) do
    Fixtures.write!(home, Path.join(directory, "new/benchmark.json"), JSON.encode!(benchmark))
    Fixtures.write!(home, Path.join(directory, "new/estimates.json"), JSON.encode!(estimates))
    # criterion keeps the previous run as the baseline; only new/ is read.
    Fixtures.write!(home, Path.join(directory, "base/benchmark.json"), "{}")
  end

  defp benchmark(id, throughput) do
    %{
      "group_id" => hd(String.split(id, "/")),
      "function_id" => nil,
      "value_str" => nil,
      "throughput" => throughput,
      "full_id" => id,
      "directory_name" => id,
      "title" => id
    }
  end

  test "keeps nanobench's tables, closes their rows and drops other output" do
    assert BenchReport.nanobench_tables(@nanobench_output) == """
           |               ns/op |                op/s |    err% |     total | queue |
           |--------------------:|--------------------:|--------:|----------:|:------ |
           |               18.29 |       54,662,954.29 |    1.0% |      0.06 | `admit` |
           |              394.15 |        2,537,086.94 |    0.7% |      0.06 | :wavy_dash: `flush` |

           |             ns/byte |              byte/s |    err% |     total | benchmark |
           |--------------------:|--------------------:|--------:|----------:|:---------- |
           |                0.25 |    4,000,000,000.00 |    0.1% |      0.01 | `copy` |\
           """

    assert BenchReport.nanobench_tables("|a|b|\n|--|--|\n|1|2|") == "|a|b|\n|--|--|\n|1|2|"
    assert BenchReport.nanobench_tables("no table\n") == ""
  end

  test "renders a report with a title, a description, the system and the results" do
    report =
      BenchReport.render(%{
        title: "Bounded queue",
        description: "Admission and drain.\n",
        system: [{"Operating system", "Linux"}, {"Compiler", "clang version 23.1.1"}],
        results: "| a |\n| -- |\n| 1 |\n",
        note: "A note."
      })

    assert report == """
           # Bounded queue

           Admission and drain.

           ## System

           - Operating system: Linux
           - Compiler: clang version 23.1.1

           ## Results

           | a |
           | -- |
           | 1 |

           A note.
           """

    refute BenchReport.render(%{
             title: "T",
             description: "D",
             system: [],
             results: "r",
             note: nil
           }) =~ "\n\n\n"
  end

  test "reads criterion's estimates and converts them to a Markdown table" do
    home = Fixtures.tmp_dir("criterion")
    write_criterion(home, "sized/64", benchmark("sized/64", %{"Bytes" => 512}), @estimates)

    write_criterion(
      home,
      "sum 1024",
      benchmark("sum 1024", nil),
      put_in(@estimates, ["mean", "point_estimate"], 57_114.2)
    )

    write_criterion(
      home,
      "sized/elements",
      benchmark("sized/elements", %{"Elements" => 1024}),
      put_in(@estimates, ["mean", "point_estimate"], 57.62)
    )

    assert {:ok, [sized, elements, sum]} = BenchReport.criterion(home)
    assert elements.id == "sized/elements"
    assert sized.throughput == %{"Bytes" => 512}
    assert sum.mean == 57_114.2
    assert sum.throughput == nil

    assert BenchReport.criterion_table([sized, elements, sum]) == """
           | Benchmark | Mean | Median | Std. dev. | Throughput |
           | :-- | --: | --: | --: | --: |
           | `sized/64` | 3.488 ns | 3.474 ns | 0.063 ns | 136.7 GiB/s |
           | `sized/elements` | 57.62 ns | 3.474 ns | 0.063 ns | 17.77 Gelem/s |
           | `sum 1024` | 57.11 µs | 3.474 ns | 0.063 ns | - |\
           """

    # Without a declared throughput the column is left out.
    assert BenchReport.criterion_table([sum]) =~
             ~r/^\| Benchmark \| Mean \| Median \| Std\. dev\. \|\n/
  end

  test "reports an unreadable criterion record" do
    home = Fixtures.tmp_dir("criterion-broken")
    write_criterion(home, "a", benchmark("a", nil), Map.delete(@estimates, "median"))
    assert {:error, "a/new/benchmark.json: no median point estimate"} = BenchReport.criterion(home)

    Fixtures.write!(home, "a/new/estimates.json", "not json")
    assert {:error, "a/new/benchmark.json: invalid JSON"} = BenchReport.criterion(home)

    assert {:error, "not a criterion benchmark record"} = BenchReport.estimate(%{}, @estimates)
    assert {:ok, []} = BenchReport.criterion(Fixtures.tmp_dir("criterion-empty"))
  end

  test "formats durations and throughput as criterion prints them" do
    assert BenchReport.duration(3.48751) == "3.488 ns"
    assert BenchReport.duration(57.114) == "57.11 ns"
    assert BenchReport.duration(123.44) == "123.4 ns"
    assert BenchReport.duration(12_345.0) == "12.35 µs"
    assert BenchReport.duration(2.5e7) == "25.00 ms"
    assert BenchReport.duration(3.0e9) == "3.000 s"

    # 1 KiB per microsecond.
    assert BenchReport.throughput(%{"Bytes" => 1024}, 1000) == "976.6 MiB/s"
    assert BenchReport.throughput(%{"BytesDecimal" => 1000}, 1000) == "1.000 GB/s"
    assert BenchReport.throughput(%{"Elements" => 1}, 1000) == "1.000 Melem/s"
    assert BenchReport.throughput(%{"Elements" => 1}, 1.0e10) == "0.100 elem/s"

    assert BenchReport.throughput(
             %{"ElementsAndBytes" => %{"elements" => 2, "bytes" => 2048}},
             1000
           ) ==
             "2.000 Melem/s, 1.907 GiB/s"

    assert BenchReport.throughput(nil, 1000) == nil
    assert BenchReport.throughput(%{"Other" => 1}, 1000) == nil
    assert BenchReport.throughput(%{"Bytes" => 1}, 0) == nil
  end

  test "escapes a pipe in a benchmark id" do
    estimate = %{id: "a|b", mean: 1.0, median: 1.0, std_dev: 0.1, throughput: nil}
    assert BenchReport.criterion_table([estimate]) =~ "| `a\\|b` |"
  end
end
