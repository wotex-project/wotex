Code.require_file("support/simulations.exs", __DIR__)

alias Wotex.Lab.Bench.Simulations
alias Wotex.Lab.Error
alias Wotex.Lab.Simulators.Thermal

inputs = Map.new(Simulations.sizes(), fn {label, count} -> {label, Simulations.input(count)} end)

Benchee.run(
  %{
    "admit and simulate" => fn %{options: options, count: count} ->
      %{samples: [%{index: 0, quality: :good} | _], manifest: %{"count" => ^count}} =
        Thermal.generate(options)
    end,
    "admit and reject" => fn %{rejected: options} ->
      {:error, %Error{code: :invalid_simulation}} = Thermal.generate(options)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/thermal_simulator.md",
     title: "# Thermal simulator",
     description: """
     `Wotex.Lab.Simulators.Thermal.generate/1`, the deterministic first-order
     room temperature simulator that supplies the synthetic observations of
     the Nx lanes, with a step of 60,000 and the default 32 samples, 512
     samples and the 4,096-sample maximum. The heater schedule adds 0.5 °C at
     every 16th sample (256 entries at the maximum, the schedule bound) and
     every 64th sample from index 7 is a glitch reported with `:bad` quality.

     `admit and simulate` validates every option and schedule entry, then
     runs the model with its seeded linear congruential noise and returns
     the samples and the manifest. `admit and reject` passes the same
     options with one glitch index past the last sample: admission checks
     every entry and returns `:invalid_simulation`, which isolates the cost
     of admission. No Nx tensor is built.
     """}
  ]
)
