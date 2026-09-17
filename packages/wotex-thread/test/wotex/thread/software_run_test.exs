defmodule Wotex.Thread.SoftwareRunTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Thread.Software.Run

  @moduletag requirements: ["WTH-B01", "WTH-B03"]

  @required [
    %{"module" => "M", "name" => "test first"},
    %{"module" => "M", "name" => "test second"}
  ]

  test "WTH-B01 software run accepts exactly one absolute workspace" do
    workspace = Path.join(System.tmp_dir!(), "wotex-thread-software-run")
    assert {:ok, ^workspace} = Run.arguments(["--workspace", workspace])

    for args <- [[], ["--workspace", "relative"], ["--workspace", workspace, "--seed", "0"]] do
      assert {:error, :invalid_software_run_arguments} = Run.arguments(args)
    end

    assert {:error, :invalid_software_run_arguments} = Run.run(nil)
  end

  unless match?({:unix, :linux}, :os.type()) do
    test "WTH-B01 software runs require Linux before reading the workspace" do
      assert {:error, :linux_required} = Run.run("/missing/software-workspace")
    end
  end

  test "WTH-B03 a lane is accepted only when every required case passed exactly once" do
    assert %{"accepted" => true, "cases" => 3, "passed" => 3} =
             Run.evaluate(
               @required,
               lines([
                 {"test first", "passed"},
                 {"test second", "passed"},
                 {"test extra", "passed"}
               ])
             )

    for {cases, key} <- [
          {[{"test first", "passed"}], "missing_or_not_passed"},
          {[{"test first", "passed"}, {"test second", "failed"}], "not_passed"},
          {[{"test first", "passed"}, {"test second", "skipped"}], "not_passed"},
          {[{"test first", "passed"}, {"test second", "invalid"}], "not_passed"},
          {[{"test first", "passed"}, {"test second", "passed"}, {"test second", "passed"}],
           "duplicates"},
          {[{"test first", "passed"}, {"test second", "passed"}, {"test other", "failed"}],
           "not_passed"}
        ] do
      evaluation = Run.evaluate(@required, lines(cases))
      refute evaluation["accepted"], inspect(cases)
      assert evaluation[key] != [], inspect({key, evaluation})
    end

    assert %{"accepted" => false, "cases" => 0} = Run.evaluate(@required, "")
    assert %{"accepted" => false} = Run.evaluate([], lines([{"test first", "passed"}]))

    malformed =
      lines([{"test first", "passed"}, {"test second", "passed"}]) <>
        "{\"module\":\"M\"}\nnot json\n"

    assert %{"accepted" => false, "malformed_lines" => 2} = Run.evaluate(@required, malformed)
  end

  defp lines(cases) do
    Enum.map_join(cases, fn {name, state} ->
      Jason.encode!(%{"module" => "M", "name" => name, "state" => state}) <> "\n"
    end)
  end
end
