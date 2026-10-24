source = Path.expand("../../../bin/check_transition_corpus.exs", __DIR__)
{:__block__, _, forms} = Code.string_to_quoted!(File.read!(source))

module =
  Enum.find(forms, fn
    {:defmodule, _, [{:__aliases__, _, [:Wotex, :Routines, :TransitionCorpus]}, _]} -> true
    _ -> false
  end)

Code.compile_quoted(module, source)

defmodule Wotex.Routines.TransitionCorpusRunnerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.TransitionCorpus

  test "only the complete current corpus with assertion-only failures qualifies" do
    valid = %{total: 13, failures: 1, skipped: 0, excluded: 0}
    assertions = %{assertions: 1, errors: 0}
    assert TransitionCorpus.mutation_valid?(valid, assertions)

    for {result, counts} <- [
          {%{valid | total: 12}, assertions},
          {%{valid | total: 14}, assertions},
          {%{valid | failures: 0}, %{assertions | assertions: 0}},
          {%{valid | failures: 14}, %{assertions | assertions: 14}},
          {valid, %{assertions | assertions: 2}},
          {valid, %{assertions | errors: 1}},
          {%{valid | skipped: 1}, assertions},
          {%{valid | excluded: 1}, assertions},
          {Map.put(valid, :unexpected, 1), assertions},
          {valid, Map.put(assertions, :unexpected, 1)},
          {%{valid | failures: "1"}, assertions},
          {:invalid, assertions},
          {valid, :invalid}
        ] do
      refute TransitionCorpus.mutation_valid?(result, counts)
    end
  end

  test "the actual point mutation entry accepts all current transition tests" do
    script = Path.expand("../../../bin/check_transition_corpus.exs", __DIR__)
    paths = Enum.flat_map(:code.get_path(), &["-pa", to_string(&1)])

    environment = [
      {"WOTEX_PATH_DEPS", nil},
      {"WOTEX_ROUTINES_COMPILER_BASIS", nil},
      {"MIX_ENV", nil},
      {"MIX_BUILD_PATH", nil},
      {"MIX_BUILD_ROOT", nil},
      {"MIX_DEPS_PATH", nil}
    ]

    {output, status} =
      System.cmd("elixir", paths ++ [script, "--mutant", "point_basis"],
        cd: File.cwd!(),
        env: environment,
        stderr_to_stdout: true
      )

    assert status == 0, output
    [[_, marker]] = Regex.scan(~r/^POINT_MUTANT (.+)$/m, output)
    result = JSON.decode!(marker)
    assert result["name"] == "point_basis"
    assert result["tests"] == 13
    assert result["errors"] == 0
    assert result["failures"] > 0
    assert result["assertions"] == result["failures"]
  end
end
