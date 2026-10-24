Code.require_file("../../../bin/decision_consumers.exs", __DIR__)

defmodule Wotex.Routines.DecisionArchiveRunnerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.Check.DecisionConsumers

  test "only a complete passing baseline or assertion-only semantic catch is evidence" do
    for {baseline_count, mutation_count} <- [{41, 40}, {59, 25}] do
      baseline = marker(baseline_count, 0, 0, 0)
      mutant = marker(mutation_count, 2, 2, 0)
      assert {:ok, _} = DecisionConsumers.validate(baseline, 0, baseline_count, false)
      assert {:ok, _} = DecisionConsumers.validate(mutant, 1, mutation_count, true)

      for {output, status, total, mutant?} <- [
            {baseline, 1, baseline_count, false},
            {marker(8, 0, 0, 0), 0, baseline_count, false},
            {marker(7, 1, 1, 0), 1, mutation_count, true},
            {mutant, 0, mutation_count, true},
            {marker(mutation_count, 0, 0, 0), 0, mutation_count, true},
            {marker(mutation_count, 2, 1, 1), 1, mutation_count, true},
            {marker(mutation_count, 2, 1, 0), 1, mutation_count, true},
            {marker(mutation_count - 1, 1, 1, 0), 1, mutation_count, true},
            {marker(mutation_count, 1, 1, 0, skipped: 1), 1, mutation_count, true},
            {marker(mutation_count, 1, 1, 0, excluded: 1), 1, mutation_count, true},
            {baseline <> baseline, 0, baseline_count, false},
            {"DECISION_RESULT={}\nDECISION_ASSERTIONS={}\n", 0, baseline_count, false},
            {"DECISION_RESULT=invalid\nDECISION_ASSERTIONS={}\n", 0, baseline_count, false},
            {"compiler failure", 1, mutation_count, true}
          ] do
        assert {:error, _} = DecisionConsumers.validate(output, status, total, mutant?)
      end
    end
  end

  test "fresh VMs load the full baseline and selected fault corpus without test filters" do
    temporary =
      Path.join(System.tmp_dir!(), "wotex-decision-selector-#{System.unique_integer([:positive])}")

    tests = Path.join(temporary, "test")
    File.mkdir_p!(tests)

    on_exit(fn -> File.rm_rf!(temporary) end)

    for {file, label} <- [
          {"identity.exs", "identity"},
          {"decision_consumer_test.exs", "original"},
          {"decision_bounds_consumer_test.exs", "bounds"},
          {"decision_time_consumer_test.exs", "time"}
        ] do
      File.write!(Path.join(tests, file), "IO.puts(#{inspect("CORPUS_FILE=" <> label)})\n")
    end

    replacement = Path.join(temporary, "replacement.ex")
    File.write!(replacement, "defmodule CorpusReplacementProbe do\n  @moduledoc false\nend\n")
    script = Path.expand("../../support/archive/decision_mutation_consumer.exs", __DIR__)

    environment = [
      {"WOTEX_PATH_DEPS", nil},
      {"WOTEX_ROUTINES_COMPILER_BASIS", nil},
      {"MIX_ENV", nil},
      {"MIX_BUILD_PATH", nil},
      {"MIX_BUILD_ROOT", nil},
      {"MIX_DEPS_PATH", nil}
    ]

    for {candidate, corpus, expected} <- [
          {"baseline", "bounds", ~w(identity original bounds)},
          {"baseline", "time", ~w(identity original bounds time)},
          {replacement, "bounds", ~w(original bounds)},
          {replacement, "time", ~w(original time)}
        ] do
      {output, status} =
        System.cmd("elixir", [script, candidate, corpus],
          cd: temporary,
          env: environment,
          stderr_to_stdout: true
        )

      assert status == 0, output
      assert Enum.map(Regex.scan(~r/^CORPUS_FILE=(.+)$/m, output), &List.last/1) == expected
      assert output =~ "DECISION_RESULT="
      assert output =~ "DECISION_ASSERTIONS="
    end

    {output, status} =
      System.cmd("elixir", [script, "baseline", "unsupported"],
        cd: temporary,
        env: environment,
        stderr_to_stdout: true
      )

    assert status != 0
    assert output =~ "unsupported decision corpus"
    refute output =~ "DECISION_RESULT="
  end

  defp marker(total, failures, assertions, errors, opts \\ []) do
    result = %{
      total: total,
      failures: failures,
      skipped: opts[:skipped] || 0,
      excluded: opts[:excluded] || 0
    }

    "DECISION_RESULT=" <>
      JSON.encode!(result) <>
      "\nDECISION_ASSERTIONS=" <>
      JSON.encode!(%{assertions: assertions, errors: errors}) <> "\n"
  end
end
