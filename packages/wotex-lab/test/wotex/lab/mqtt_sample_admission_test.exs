defmodule Wotex.Lab.MqttSampleAdmissionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Adapters.MQTT.SampleAdmission
  alias Wotex.Lab.Error
  alias Wotex.Nx.Observation

  test "fresh retained samples carry device clock and reset identity into Nx" do
    assert {:ok, first} = SampleAdmission.admit(21.5, sample_opts())
    assert {:ok, repeated} = SampleAdmission.admit(21.5, sample_opts())
    assert first == repeated

    fields = Observation.to_map(first)
    assert fields.observed_at == 9_950
    assert fields.source == "mqtt"
    assert fields.metadata["retained"]
    assert fields.metadata["clock_uncertainty_ms"] == 25
    assert fields.metadata["device_id"] == "sensor-7"
    assert fields.metadata["boot_id"] == "boot-a"

    assert {:ok, reset} =
             SampleAdmission.admit(21.5, Keyword.replace(sample_opts(), :boot_id, "boot-b"))

    refute Observation.to_map(reset).id == fields.id
  end

  test "stale, future and malformed samples never become observations" do
    assert {:error, %Error{code: :stale_retained_sample}} =
             SampleAdmission.admit(
               21.5,
               sample_opts(observed_at: 1_000, received_at: 10_000, max_age_ms: 1_000)
             )

    assert {:error, %Error{code: :stale_mqtt_sample}} =
             SampleAdmission.admit(
               21.5,
               sample_opts(
                 observed_at: 1_000,
                 received_at: 10_000,
                 max_age_ms: 1_000,
                 retained: false
               )
             )

    assert {:error, %Error{code: :mqtt_sample_from_future}} =
             SampleAdmission.admit(21.5, sample_opts(observed_at: 10_100, received_at: 10_000))

    assert {:error, %Error{code: :invalid_mqtt_sample}} =
             SampleAdmission.admit(21.5, sample_opts(boot_id: ""))

    assert {:error, %Error{code: :invalid_options}} =
             SampleAdmission.admit(21.5, sample_opts(secret: "not-admitted"))
  end

  defp sample_opts(overrides \\ []) do
    Keyword.merge(
      [
        thing_id: "urn:wotex:lab:mqtt:sensor-7",
        affordance_name: "temperature",
        device_id: "sensor-7",
        boot_id: "boot-a",
        sequence: 41,
        observed_at: 9_950,
        received_at: 10_000,
        clock_uncertainty_ms: 25,
        max_age_ms: 100,
        retained: true,
        unit: "Cel"
      ],
      overrides
    )
  end
end
