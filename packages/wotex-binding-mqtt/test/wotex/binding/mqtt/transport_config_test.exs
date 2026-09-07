defmodule Wotex.Binding.MQTT.TransportConfigTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.MQTT.{Error, TransportConfig}
  alias Wotex.Binding.MQTT.Test.FakeClient

  test "builds bounded, credential-free transport configuration" do
    client_config = %{connection: :caller_owned, hidden_marker: "do-not-inspect"}

    assert {:ok, config} =
             TransportConfig.new(FakeClient, client_config,
               read_timeout: 250,
               max_payload_bytes: 2_048
             )

    assert TransportConfig.read_timeout(config) == 250
    assert TransportConfig.max_payload_bytes(config) == 2_048
    assert inspect(config) =~ "FakeClient"
    refute inspect(config) =~ "do-not-inspect"
  end

  test "uses finite defaults" do
    assert {:ok, config} = TransportConfig.new(FakeClient, %{test_pid: self()})
    assert TransportConfig.read_timeout(config) == 5_000
    assert TransportConfig.max_payload_bytes(config) == 1_048_576
  end

  test "rejects missing client callbacks and invalid construction input" do
    assert_error(TransportConfig.new(__MODULE__, %{}), :invalid_client_port)
    assert_error(TransportConfig.new(nil, %{}), :invalid_transport_configuration)
    assert_error(TransportConfig.new(FakeClient, %{}, :options), :invalid_transport_configuration)
  end

  test "rejects unknown, non-keyword, and non-positive options" do
    assert_error(TransportConfig.new(FakeClient, %{}, unknown: true), :invalid_transport_options)

    assert_error(
      TransportConfig.new(FakeClient, %{}, [{:read_timeout, 10}, :bad]),
      :invalid_transport_options
    )

    assert_error(TransportConfig.new(FakeClient, %{}, read_timeout: 0), :invalid_transport_option)

    assert_error(
      TransportConfig.new(FakeClient, %{}, max_payload_bytes: -1),
      :invalid_transport_option
    )
  end

  defp assert_error(result, code) do
    assert {:error, %Error{code: ^code, phase: :configuration} = error} = result
    assert Error.class(error) == :permanent
  end
end
