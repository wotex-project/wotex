defmodule Wotex.Lab.Bench.Simulations do
  @moduledoc false

  # Thermal simulations with a step of 60,000: the default 32 samples, 512
  # samples and the simulator's 4,096-sample maximum. The heater adds 0.5 °C
  # at every 16th sample (256 entries at the maximum, the schedule bound) and
  # every 64th sample from index 7 is a glitch. The rejected variant appends
  # one glitch index past the last sample, so admission checks every
  # schedule entry before it refuses the input.

  @spec sizes() :: %{String.t() => pos_integer()}
  def sizes, do: %{"32 samples" => 32, "512 samples" => 512, "4096 samples" => 4_096}

  @spec input(pos_integer()) :: map()
  def input(count) do
    glitches = Enum.take_every(7..(count - 1), 64)

    options = [
      seed: 42,
      step: 60_000,
      count: count,
      heater: Map.new(0..(count - 1)//16, &{&1, 0.5}),
      glitches: glitches
    ]

    %{
      count: count,
      options: options,
      rejected: Keyword.put(options, :glitches, Enum.concat(glitches, [count]))
    }
  end
end
