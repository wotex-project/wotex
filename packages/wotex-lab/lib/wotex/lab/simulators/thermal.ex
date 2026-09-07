defmodule Wotex.Lab.Simulators.Thermal do
  @moduledoc """
  A versioned, deterministic first-order room temperature simulator.

  Every input is explicit: seed, time step, sample count, initial temperature,
  ambient temperature, coupling coefficient, a heater schedule and a glitch
  schedule. The model is

      T[n+1] = T[n] + k * (ambient - T[n]) + heater[n] + noise[n]

  where `noise[n]` comes from a linear congruential generator seeded by the
  caller, so the same inputs produce the same samples on every node and OTP
  release. Samples at glitch indices carry `:bad` quality with an out-of-range
  value, the way a failing sensor does. All values are synthetic Celsius.
  """

  @version "1.0.0"
  @lcg_multiplier 6_364_136_223_846_793_005
  @lcg_increment 1_442_695_040_888_963_407
  @lcg_modulus Bitwise.bsl(1, 64)

  @type sample :: %{
          index: non_neg_integer(),
          observed_at: integer(),
          value: float(),
          quality: :good | :bad
        }

  @doc "Returns the simulator version recorded in experiment manifests."
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Generates `count` samples starting at coordinate `start` every `step`.

  Options: `:seed` (default 1), `:step` (default 1_000), `:count` (default 32),
  `:start` (default 0), `:initial` (20.0), `:ambient` (18.0), `:coupling`
  (0.1), `:noise` amplitude (0.05), `:heater` as a map of index to added
  degrees, and `:glitches` as a list of indices reported with `:bad` quality.
  """
  @spec generate(keyword()) :: %{samples: [sample()], manifest: map()}
  def generate(opts \\ []) do
    seed = Keyword.get(opts, :seed, 1)
    step = Keyword.get(opts, :step, 1_000)
    count = Keyword.get(opts, :count, 32)
    start = Keyword.get(opts, :start, 0)
    initial = Keyword.get(opts, :initial, 20.0)
    ambient = Keyword.get(opts, :ambient, 18.0)
    coupling = Keyword.get(opts, :coupling, 0.1)
    noise = Keyword.get(opts, :noise, 0.05)
    heater = Keyword.get(opts, :heater, %{})
    glitches = Keyword.get(opts, :glitches, [])

    {samples, _state} =
      Enum.map_reduce(0..(count - 1)//1, {initial * 1.0, seed}, fn index, {temperature, lcg} ->
        {jitter, next_lcg} = next_noise(lcg, noise)

        sample =
          if index in glitches,
            do: %{index: index, observed_at: start + index * step, value: -273.15, quality: :bad},
            else: %{
              index: index,
              observed_at: start + index * step,
              value: temperature,
              quality: :good
            }

        next =
          temperature + coupling * (ambient - temperature) + Map.get(heater, index, 0.0) + jitter

        {sample, {next, next_lcg}}
      end)

    manifest = %{
      "simulator" => "wotex_lab.thermal",
      "version" => @version,
      "equation" => "T[n+1] = T[n] + k * (ambient - T[n]) + heater[n] + noise[n]",
      "unit" => "Cel",
      "seed" => seed,
      "step" => step,
      "count" => count,
      "start" => start,
      "initial" => initial,
      "ambient" => ambient,
      "coupling" => coupling,
      "noise_amplitude" => noise,
      "heater" => heater,
      "glitches" => glitches,
      "source_mode" => "synthetic"
    }

    %{samples: samples, manifest: manifest}
  end

  defp next_noise(state, amplitude) do
    next = rem(state * @lcg_multiplier + @lcg_increment, @lcg_modulus)
    unit = Bitwise.bsr(next, 11) / Bitwise.bsl(1, 53)
    {(unit * 2.0 - 1.0) * amplitude, next}
  end
end
