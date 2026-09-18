Code.require_file("support/series.exs", __DIR__)

alias Wotex.Nx.Bench.Series
alias Wotex.Nx.Window

inputs =
  Map.new(Series.sizes(), fn {label, {feature_count, row_count}} ->
    readings = Series.readings(feature_count, row_count)
    observations = Series.observations(readings)

    windows =
      Map.new([:latest, :nearest], fn strategy ->
        {:ok, window} =
          Window.new(
            start: 0,
            step: Series.step(),
            count: row_count,
            strategy: strategy,
            max_age: Series.step()
          )

        {strategy, window}
      end)

    {label,
     %{
       readings: readings,
       observations: observations,
       schema: Series.schema(feature_count, row_count),
       windows: windows,
       limits: [max_observations: length(observations)]
     }}
  end)

resample = fn input, strategy ->
  {:ok, [_ | _]} =
    Window.resample(input.observations, input.schema, input.windows[strategy], input.limits)
end

Benchee.run(
  %{
    "Observation.new (every reading)" => fn %{readings: readings} ->
      [_ | _] = Series.observations(readings)
    end,
    "resample :latest" => fn input -> resample.(input, :latest) end,
    "resample :nearest" => fn input -> resample.(input, :nearest) end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/window.md",
     title: "# Observation admission and window resampling",
     description: """
     One Property observation per feature and 1,000 ms step, with a deterministic
     jitter below half a step, for 4, 16 and 64 features over 32, 128 and 512
     steps (128, 2,048 and 32,768 observations). `Wotex.Nx.Observation.new/1`
     admits every reading; `Wotex.Nx.Window.resample/4` selects schema-ordered
     rows on the step grid with the `:latest` and `:nearest` strategies and a
     maximum age of one step, with `:max_observations` raised to the input size.
     """}
  ]
)
