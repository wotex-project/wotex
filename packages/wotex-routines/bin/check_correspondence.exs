defmodule Wotex.Routines.CorrespondenceAssertions do
  @moduledoc false

  use GenServer

  def init(_), do: {:ok, %{assertions: 0, errors: 0}}

  def handle_cast({:test_finished, %{state: {:failed, failures}}}, state) do
    assertions = Enum.count(failures, &match?({:error, %ExUnit.AssertionError{}, _}, &1))

    {:noreply,
     %{
       assertions: state.assertions + assertions,
       errors: state.errors + length(failures) - assertions
     }}
  end

  def handle_cast({:suite_finished, _}, state) do
    IO.puts("CORRESPONDENCE_ASSERTIONS=" <> JSON.encode!(state))
    {:noreply, state}
  end

  def handle_cast(_, state), do: {:noreply, state}
end

defmodule Wotex.Routines.CorrespondenceCheck do
  @moduledoc false

  @mutations [
    {"comparison_unknown", "predicate_machine.ex", "defp compare(_, _, _), do: \"unknown\"",
     "defp compare(_, _, _), do: false"},
    {"ack_completion", "receipt.ex",
     "threshold = Enum.find_index(@stages, &(&1 == node[\"completion\"]))",
     "threshold = min(1, Enum.find_index(@stages, &(&1 == node[\"completion\"])))"},
    {"parallel_branch", "execution.ex",
     "Enum.reduce_while(children, {:ok, state}, fn child, {:ok, state} ->",
     "Enum.reduce_while(Enum.take(children, 1), {:ok, state}, fn child, {:ok, state} ->"},
    {"root_deadline", "kernel.ex", "time[\"elapsed_ms\"] >= run[\"deadline_ms\"] ->", "false ->"},
    {"held_spend", "receipt.ex", "\"spent\" => spending(steps)",
     "\"spent\" => Enum.take(spending(steps), 0)"},
    {"root_gate", "execution.ex", "defp gate(_, _, _, state), do: {:ok, %{state | blocked: true}}",
     "defp gate(_, node, deadline, state), do: visit(node, deadline, state)"}
  ]

  def run(["--child", replacement]) do
    Application.load(:wotex_routines)

    if replacement != "baseline" do
      Code.compiler_options(ignore_module_conflict: true)
      Code.compile_file(replacement)
    end

    root = Path.expand("..", __DIR__)
    Code.require_file("test/test_helper.exs", root)

    ExUnit.configure(
      autorun: false,
      seed: 0,
      formatters: [ExUnit.CLIFormatter, Wotex.Routines.CorrespondenceAssertions]
    )

    Code.require_file("test/wotex/routines/correspondence_test.exs", root)
    Code.require_file("test/wotex/routines/evaluation_test.exs", root)
    result = ExUnit.run()
    IO.puts("CORRESPONDENCE_RESULT=" <> JSON.encode!(result))
    System.halt(if result.failures == 0, do: 0, else: 1)
  end

  def run([]) do
    baseline = execute("baseline")
    ensure!(baseline.status == 0 and baseline.result["failures"] == 0, "baseline failed")
    IO.puts("baseline: #{baseline.result["total"]} tests passed")

    scratch =
      Path.join(System.tmp_dir!(), "routines-correspondence-#{System.unique_integer([:positive])}")

    File.mkdir!(scratch)

    try do
      Enum.each(@mutations, &mutation(&1, scratch, baseline.result["total"]))
    after
      File.rm_rf!(scratch)
    end

    IO.puts("#{length(@mutations)} behavioral mutations caught by executed assertions")
  end

  def run(_), do: raise("usage: mix run --no-start bin/check_correspondence.exs")

  defp mutation({name, filename, from, to}, scratch, total) do
    source = File.read!(Path.expand("../lib/wotex/routines/#{filename}", __DIR__))
    ensure!(length(String.split(source, from)) == 2, "mutation site changed: #{name}")
    path = Path.join(scratch, filename)
    File.write!(path, String.replace(source, from, to, global: false))
    run = execute(path)

    ensure!(
      run.status == 1 and run.result["total"] == total and run.result["failures"] > 0,
      "mutation survived or harness failed: #{name}"
    )

    ensure!(
      run.assertions["assertions"] > 0 and run.assertions["errors"] == 0,
      "mutation did not fail exclusively through assertions: #{name}"
    )

    IO.puts("#{name}: #{run.result["failures"]} asserting failures")
  end

  defp execute(replacement) do
    executable = System.find_executable("elixir") || raise "Elixir executable unavailable"
    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])
    arguments = paths ++ [Path.expand(__ENV__.file), "--child", replacement]
    task = Task.async(fn -> System.cmd(executable, arguments, stderr_to_stdout: true) end)

    case Task.yield(task, 30_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, status}} -> parse(output, status)
      _ -> raise "correspondence process timed out"
    end
  end

  defp parse(output, status) do
    result =
      output |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "CORRESPONDENCE_RESULT="))

    ensure!(result != nil, "correspondence compile/process failure")

    assertions =
      output
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, "CORRESPONDENCE_ASSERTIONS="))

    ensure!(assertions != nil, "assertion formatter failed")

    %{
      output: output,
      status: status,
      assertions:
        assertions |> String.replace_prefix("CORRESPONDENCE_ASSERTIONS=", "") |> JSON.decode!(),
      result: result |> String.replace_prefix("CORRESPONDENCE_RESULT=", "") |> JSON.decode!()
    }
  end

  defp ensure!(true, _), do: :ok
  defp ensure!(false, message), do: raise(message)
end

Wotex.Routines.CorrespondenceCheck.run(System.argv())
