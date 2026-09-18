alias WotexContinuum.Lifecycle

{:ok, staged} =
  Lifecycle.from_map(%{
    "kind" => "lifecycle",
    "schema_version" => WotexContinuum.schema_version(),
    "subject_id" => "worker-example-1",
    "state" => "staged",
    "generation" => 0,
    "changed_at" => "2026-09-02T10:00:00Z",
    "extensions" => %{}
  })

# One recorded change per second through the cycle ready, active, degraded,
# active, draining, stopped, which returns to ready.
cycle = [:ready, :active, :degraded, :active, :draining, :stopped]

log = fn count ->
  cycle
  |> Stream.cycle()
  |> Stream.take(count)
  |> Enum.with_index(1)
  |> Enum.map(fn {state, second} ->
    {state, DateTime.add(~U[2026-09-02 10:00:00Z], second, :second)}
  end)
end

inputs =
  Map.new(
    %{"6 transitions" => 6, "60 transitions" => 60, "600 transitions" => 600},
    fn {label, count} -> {label, %{count: count, log: log.(count)}} end
  )

Benchee.run(
  %{
    "replay with transition/4" => fn %{count: count, log: log} ->
      %Lifecycle{generation: ^count} =
        Enum.reduce(log, staged, fn {state, changed_at}, lifecycle ->
          {:ok, next} = Lifecycle.transition(lifecycle, state, changed_at)
          next
        end)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/lifecycle.md",
     title: "# Lifecycle replay",
     description: """
     Replays a recorded lifecycle of 6, 60 and 600 changes from `staged` with
     `WotexContinuum.Lifecycle.transition/4`, one `DateTime` per second through
     the cycle `ready`, `active`, `degraded`, `active`, `draining`, `stopped`.
     Every step revalidates the current value, admits only an edge of the
     transition graph, checks that time does not decrease and increments the
     generation.
     """}
  ]
)
