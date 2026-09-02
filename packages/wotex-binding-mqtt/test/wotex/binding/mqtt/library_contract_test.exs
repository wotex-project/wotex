defmodule Wotex.Binding.MQTT.LibraryContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.MQTT
  alias Wotex.Runtime.BindingProfile

  test "profile declares the supported Runtime boundary" do
    profile = MQTT.profile()

    assert BindingProfile.id(profile) == :mqtt
    assert BindingProfile.supports_scheme?(profile, "mqtt")
    assert BindingProfile.supports_scheme?(profile, "mqtts")
    assert BindingProfile.supports_operation?(profile, :readproperty)
    assert BindingProfile.supports_operation?(profile, :subscribeevent)
    assert BindingProfile.supports_media_type?(profile, "application/json; charset=utf-8")
    refute BindingProfile.supports_operation?(profile, :queryaction)
  end

  test "package defines no OTP application module" do
    refute Code.ensure_loaded?(Wotex.Binding.MQTT.Application)
    assert {:ok, []} = :application.get_key(:wotex_binding_mqtt, :mod)
  end
end
