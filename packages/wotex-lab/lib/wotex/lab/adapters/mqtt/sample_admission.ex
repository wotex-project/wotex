defmodule Wotex.Lab.Adapters.MQTT.SampleAdmission do
  @moduledoc """
  Turns a device-timestamped MQTT sample into a numerical observation.

  MQTT receipt time is not treated as sensor observation time. Callers must
  supply a bounded device clock uncertainty, age policy, device identifier,
  boot identifier and sequence. The resulting observation identity changes on
  a device reset, and a stale retained value is refused before it can enter a
  `Wotex.Nx` row.
  """

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Nx.Observation

  @options [
    :affordance_name,
    :boot_id,
    :clock_uncertainty_ms,
    :device_id,
    :max_age_ms,
    :observed_at,
    :quality,
    :received_at,
    :retained,
    :sequence,
    :thing_id,
    :unit
  ]

  @doc "Admits one timestamped MQTT value as an inert numerical observation."
  @spec admit(term(), keyword()) :: {:ok, Observation.t()} | {:error, Error.t() | term()}
  def admit(value, opts) do
    with :ok <- Options.validate(opts, @options),
         {:ok, sample} <- validate(opts),
         :ok <- fresh(sample) do
      Observation.new(
        id: identity(sample),
        thing_id: sample.thing_id,
        affordance_type: :property,
        affordance_name: sample.affordance_name,
        observed_at: sample.observed_at,
        value: value,
        unit: sample.unit,
        quality: sample.quality,
        source: "mqtt",
        metadata: %{
          "device_id" => sample.device_id,
          "boot_id" => sample.boot_id,
          "sequence" => sample.sequence,
          "received_at" => sample.received_at,
          "clock_uncertainty_ms" => sample.clock_uncertainty_ms,
          "retained" => sample.retained
        }
      )
    end
  end

  defp validate(opts) do
    sample = %{
      thing_id: Keyword.get(opts, :thing_id),
      affordance_name: Keyword.get(opts, :affordance_name),
      device_id: Keyword.get(opts, :device_id),
      boot_id: Keyword.get(opts, :boot_id),
      sequence: Keyword.get(opts, :sequence),
      observed_at: Keyword.get(opts, :observed_at),
      received_at: Keyword.get(opts, :received_at),
      clock_uncertainty_ms: Keyword.get(opts, :clock_uncertainty_ms, 0),
      max_age_ms: Keyword.get(opts, :max_age_ms, 60_000),
      retained: Keyword.get(opts, :retained, false),
      quality: Keyword.get(opts, :quality, :good),
      unit: Keyword.get(opts, :unit)
    }

    if valid_sample?(sample) do
      {:ok, sample}
    else
      {:error, Error.new(:invalid_mqtt_sample, :admission, "MQTT sample metadata is invalid")}
    end
  end

  defp valid_sample?(sample) do
    Enum.all?([
      text?(sample.thing_id, 512),
      text?(sample.affordance_name, 256),
      text?(sample.device_id, 256),
      text?(sample.boot_id, 256),
      integer_in?(sample.sequence, 0..9_007_199_254_740_991),
      safe_time?(sample.observed_at),
      safe_time?(sample.received_at),
      integer_in?(sample.clock_uncertainty_ms, 0..60_000),
      integer_in?(sample.max_age_ms, 0..86_400_000),
      is_boolean(sample.retained),
      sample.quality in Observation.qualities(),
      is_nil(sample.unit) or text?(sample.unit, 64)
    ])
  end

  defp fresh(sample) do
    age = sample.received_at - sample.observed_at

    cond do
      age < -sample.clock_uncertainty_ms ->
        {:error,
         Error.new(:mqtt_sample_from_future, :admission, "MQTT sample time is in the future")}

      age - sample.clock_uncertainty_ms > sample.max_age_ms and sample.retained ->
        {:error, Error.new(:stale_retained_sample, :admission, "retained MQTT sample is too old")}

      age - sample.clock_uncertainty_ms > sample.max_age_ms ->
        {:error, Error.new(:stale_mqtt_sample, :admission, "MQTT sample is too old")}

      true ->
        :ok
    end
  end

  defp identity(sample) do
    digest =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary({sample.device_id, sample.boot_id, sample.sequence})
      )
      |> Base.url_encode64(padding: false)

    "mqtt-sample-" <> digest
  end

  defp text?(value, limit),
    do: is_binary(value) and byte_size(value) in 1..limit and String.valid?(value)

  defp integer_in?(value, range), do: is_integer(value) and value in range

  defp safe_time?(value),
    do: is_integer(value) and abs(value) <= 9_007_199_254_740_991
end
