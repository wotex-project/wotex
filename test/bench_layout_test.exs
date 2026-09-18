defmodule WotexWorkspace.BenchLayoutTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace

  defp packages do
    Workspace.root()
    |> Path.join("packages/*/mix.exs")
    |> Path.wildcard()
    |> Enum.map(&Path.dirname/1)
  end

  test "every package has Elixir benchmarks with a report for each script" do
    problems =
      for package <- packages(),
          problem <- problems(package),
          do: "#{Path.basename(package)}: #{problem}"

    assert problems == [], Enum.join(problems, "\n")
  end

  defp problems(package) do
    scripts = Path.wildcard(Path.join(package, "bench/*_bench.exs"))
    mix_exs = File.read!(Path.join(package, "mix.exs"))

    missing_reports =
      for script <- scripts,
          report =
            Path.join([package, "bench/output", Path.basename(script, "_bench.exs") <> ".md"]),
          not File.regular?(report),
          do: "no report #{Path.relative_to(report, package)}"

    Enum.reject(
      [
        if(scripts == [], do: "no bench/*_bench.exs"),
        if(not String.contains?(mix_exs, ~s|{:benchee, |), do: "no benchee dependency"),
        if(not String.contains?(mix_exs, "bench/output/*.md"), do: "reports not in ExDoc extras")
      ],
      &is_nil/1
    ) ++ missing_reports
  end
end
