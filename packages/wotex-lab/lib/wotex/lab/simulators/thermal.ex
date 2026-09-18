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

  alias Wotex.Lab.{Error, Options}

  @version "1.0.0"
  @lcg_multiplier 6_364_136_223_846_793_005
  @lcg_increment 1_442_695_040_888_963_407
  @lcg_modulus Bitwise.bsl(1, 64)
  @max_samples 4_096
  @max_schedule_entries 256
  @options [:ambient, :count, :coupling, :glitches, :heater, :initial, :noise, :seed, :start, :step]

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
  @spec generate(keyword()) :: %{samples: [sample()], manifest: map()} | {:error, Error.t()}
  def generate(opts \\ []) do
    with :ok <- Options.validate(opts, @options),
         :ok <- validate(opts) do
      generate_admitted(opts)
    end
  end

  defp generate_admitted(opts) do
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

    {samples, _} =
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

  defp validate(opts) do
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

    admitted? =
      Enum.all?([
        integer_in?(seed, 0..4_294_967_295),
        integer_in?(step, 1..86_400_000),
        integer_in?(count, 2..@max_samples),
        safe_integer?(start),
        finite?(initial),
        finite?(ambient),
        number_in?(coupling, 0, 1),
        nonnegative_number?(noise),
        valid_heater?(heater, count),
        valid_glitches?(glitches, count)
      ])

    if admitted? do
      :ok
    else
      {:error, Error.new(:invalid_simulation, :construction, "thermal simulation is invalid")}
    end
  end

  defp valid_heater?(heater, count)
       when is_map(heater) and is_integer(count) and count >= 1 and
              map_size(heater) <= @max_schedule_entries do
    Enum.all?(heater, fn {index, value} ->
      is_integer(index) and index in 0..(count - 1) and finite?(value)
    end)
  end

  defp valid_heater?(_, _), do: false

  defp valid_glitches?(glitches, count)
       when is_list(glitches) and is_integer(count) and count >= 1 and
              length(glitches) <= @max_schedule_entries do
    Enum.uniq(glitches) == glitches and
      Enum.all?(glitches, &(is_integer(&1) and &1 in 0..(count - 1)))
  end

  defp valid_glitches?(_, _), do: false

  defp integer_in?(value, range) when is_integer(value), do: value in range
  defp integer_in?(_, _), do: false

  defp safe_integer?(value) when is_integer(value), do: abs(value) <= 9_007_199_254_740_991
  defp safe_integer?(_), do: false

  defp number_in?(value, minimum, maximum),
    do: finite?(value) and value >= minimum and value <= maximum

  defp nonnegative_number?(value), do: finite?(value) and value >= 0

  defp finite?(value) when is_integer(value), do: abs(value) <= 1_000_000_000_000

  defp finite?(value) when is_float(value), do: abs(value) <= 1_000_000_000_000

  defp finite?(_), do: false

  defp next_noise(state, amplitude) do
    next = rem(state * @lcg_multiplier + @lcg_increment, @lcg_modulus)
    unit = Bitwise.bsr(next, 11) / Bitwise.bsl(1, 53)
    {(unit * 2.0 - 1.0) * amplitude, next}
  end
end
