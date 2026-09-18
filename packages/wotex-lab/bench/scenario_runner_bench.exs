Code.require_file("support/echo_component.exs", __DIR__)
Code.require_file("support/runs.exs", __DIR__)

alias Wotex.Lab.Bench.Runs
alias Wotex.Lab.Runner
alias Wotex.Lab.Runner.Definition
alias Wotex.Lab.Scenario

{:ok, lab} = Wotex.Lab.start_link(id: "bench-runner", max_children: 8)
host = Runs.host(lab)
inputs = Map.new(Runs.sizes(), fn {label, count} -> {label, Runs.input(count, host)} end)

Benchee.run(
  %{
    "admit descriptor and definition" => fn input ->
      scenario = input.scenario
      definition = input.definition
      {:ok, ^scenario} = Scenario.new(input.scenario_options)
      {:ok, ^definition} = Definition.new(input.definition_options)
    end,
    "preflight" => fn %{scenario: scenario, definition: definition, host: host} ->
      :ok = Runner.preflight(scenario, definition, host)
    end,
    "start and await one attempt" =>
      {fn %{scenario: scenario, definition: definition, host: host, count: count} ->
         {:ok, run} = Runner.start(scenario, definition, host)

         {:ok, %{outcome: :pass, cleanup: :ok, steps: %{completed: ^count, failed: 0}}} =
           Runner.await(run)

         run
       end, after_each: fn run -> :ok = Wotex.Lab.stop_child(lab, :sessions, run) end}
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/scenario_runner.md",
     title: "# Scenario admission and runner attempts",
     description: """
     The scenario runner's own in-process bookkeeping over chained definitions
     of 4 steps (the length of an admitted cookbook scenario), 16 steps and
     100 steps (the default step budget). Each step depends on the step before
     it and has one assertion on its value, and the definition pins one
     packaged fixture by digest. The trusted component echoes its input and
     starts no child, so no transport, network or external process is
     involved.

     `admit descriptor and definition` is `Wotex.Lab.Scenario.new/1` and
     `Wotex.Lab.Runner.Definition.new/1` from keyword data: field and bound
     checks, unique step ids, known dependencies and the acyclicity check.
     `preflight` is `Wotex.Lab.Runner.preflight/3`: the descriptor, definition
     and host are rebuilt and compared with their constructed form, the
     descriptor and definition must agree, the host must serve every
     capability and the pinned fixture is read and digested.
     `start and await one attempt` is `Wotex.Lab.Runner.start/3` followed by
     `Wotex.Lab.Runner.await/2` until the attempt is terminal with outcome
     `pass`: preflight, placing the attempt under the instance's session
     supervisor, creating and removing its private work directory, one
     monitored worker per step in dependency order, the input and value
     digests of the replay recording, the assertions and cleanup. The
     terminal attempt is released with `Wotex.Lab.stop_child/3` outside the
     measurement; memory is that of the calling process only.
     """}
  ]
)

Supervisor.stop(lab)
File.rm_rf!(Runs.work_root())
