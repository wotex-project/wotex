defmodule Wotex.Matter.CommissioningTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter
  alias Wotex.Matter.{Descriptor, Error, OnboardingMaterial, TestClient}

  @acl %{fabric_id: 1, node_id: 9, endpoint: 0, cluster: 0x001F, member: 0}

  test "on-network commissioning requires explicit valid inputs and returns final CASE state" do
    response = %{node_id: 9, fabric_id: 1, case: :established}
    session = session(response)

    assert {:ok, ^response} =
             Matter.commission_on_network(session, %{
               node_id: 9,
               setup_pin: 20_202_021,
               discriminator: 4095,
               timeout: 60_000
             })

    assert_receive {:matter_request,
                    %{
                      type: :commission_on_network,
                      node_id: 9,
                      setup_pin: 20_202_021,
                      discriminator: 4095
                    }, 60_000}

    for pin <- [0, 99_999_999, 11_111_111, 12_345_678, 87_654_321] do
      assert {:error, %Error{code: :invalid_commissioning_request, effect: :none}} =
               Matter.commission_on_network(session, %{
                 node_id: 9,
                 setup_pin: pin,
                 discriminator: 0,
                 timeout: 1
               })
    end

    refute_receive {:matter_request, _, _}
  end

  test "commissioning failures preserve numeric SDK status and unknown effect" do
    error =
      %{Error.new(:commissioning_failed, nil, %{sdk_status: 4_052_136_097}) | effect: :unknown}

    session = session({:error, error})

    assert {:error,
            %Error{
              code: :commissioning_failed,
              details: %{sdk_status: 4_052_136_097},
              effect: :unknown
            }} =
             Matter.commission_on_network(session, %{
               node_id: 9,
               setup_pin: 20_202_021,
               discriminator: 3840,
               timeout: 5_000
             })
  end

  test "enhanced window validates bounds and redacts all onboarding values from Inspect" do
    result = %{
      node_id: 9,
      setup_pin: 20_202_021,
      discriminator: 1234,
      manual_code: "34970112332",
      qr_code: "MT:Y.K9042C00KA0648G00",
      expires_in_s: 300
    }

    session = session(result)
    request = %{node_id: 9, timeout_s: 300, iteration_count: 1_000, discriminator: 1234}

    assert {:ok, %OnboardingMaterial{} = material} =
             Matter.open_commissioning_window(session, request)

    assert material.setup_pin == 20_202_021
    assert inspect(material) == "#Wotex.Matter.OnboardingMaterial<redacted>"
    refute inspect(material) =~ result.manual_code
    refute inspect(material) =~ result.qr_code
    refute inspect(material) =~ Integer.to_string(result.setup_pin)

    assert_receive {:matter_request, %{type: :open_window} = message, 5_000}
    refute Map.has_key?(message, :setup_pin)
    refute Map.has_key?(message, :salt)

    for invalid <- [
          %{request | timeout_s: 179},
          %{request | timeout_s: 901},
          %{request | iteration_count: 999},
          %{request | iteration_count: 100_001},
          %{request | discriminator: 4096},
          Map.put(request, :setup_pin, 20_202_021)
        ] do
      assert {:error, %Error{code: :invalid_commissioning_window}} =
               Matter.open_commissioning_window(session, invalid)
    end

    refute_receive {:matter_request, _, _}
  end

  test "AccessControl ACL values are typed and PASE entries are rejected before I/O" do
    entry = %{
      privilege: 5,
      auth_mode: 2,
      subjects: [2, 0xFFFF_FFFD_0000_0001],
      targets: [%{cluster: 0x0006, endpoint: 1, device_type: nil}]
    }

    assert {:ok, element} = Descriptor.to_element(:attribute, @acl, :write, [entry])
    assert {:ok, [^entry]} = Descriptor.from_element(:attribute, @acl, :write, element)

    session = session(%{path: @acl, status: 0})
    assert {:ok, %{status: 0}} = Matter.write_attribute(session, @acl, element)
    assert_receive {:matter_request, %{type: :write, value: ^element}, 5_000}

    pase = put_in(element, [:value, Access.at(0), :value, Access.at(1), :value], 1)

    assert {:error, %Error{code: :invalid_value, effect: :none}} =
             Matter.write_attribute(session, @acl, pase)

    for target <- [
          %{cluster: nil, endpoint: nil, device_type: nil},
          %{cluster: 0x0006, endpoint: 1, device_type: 0x0100}
        ] do
      assert {:error, %Error{code: :invalid_value}} =
               Descriptor.to_element(:attribute, @acl, :write, [
                 %{entry | targets: [target]}
               ])
    end

    refute_receive {:matter_request, _, _}
  end

  test "AdministratorCommissioning values retain enum and nullable identifier bounds" do
    base = %{fabric_id: 1, node_id: 9, endpoint: 0, cluster: 0x003C}

    assert {:ok, %{type: :u8, value: 2}} =
             Descriptor.to_element(:attribute, Map.put(base, :member, 0), :read, 2)

    for {member, value, type} <- [{1, 254, :u8}, {2, 65_534, :u16}] do
      assert {:ok, %{type: ^type, value: ^value}} =
               Descriptor.to_element(:attribute, Map.put(base, :member, member), :read, value)

      assert {:ok, %{type: :null, value: nil}} =
               Descriptor.to_element(:attribute, Map.put(base, :member, member), :read, nil)
    end

    assert {:error, %Error{code: :invalid_value}} =
             Descriptor.to_element(:attribute, Map.put(base, :member, 1), :read, 0)

    assert {:error, %Error{code: :invalid_value}} =
             Descriptor.to_element(:attribute, Map.put(base, :member, 2), :read, 65_535)
  end

  test "operational ACL denial is preserved as a remote interaction status" do
    denied = Error.new(:interaction_status, nil, %{status: 126})
    session = session({:error, denied})

    assert {:error, %Error{code: :interaction_status, details: %{status: 126}}} =
             Matter.read_attribute(session, @acl)

    assert_receive {:matter_request, %{type: :read, cluster: 0x001F, member: 0}, 5_000}
  end

  test "native wire accepts final commissioning data and bounded SDK status" do
    assert {:ok, %{node_id: 9, fabric_id: 1, case: :established}} =
             Matter.Native.Wire.decode(:commission_on_network, %{
               "node_id" => 9,
               "fabric_id" => 1,
               "case" => "established"
             })

    assert {:ok,
            %Error{
              code: :commissioning_failed,
              details: %{sdk_status: 0xF1230001},
              effect: :unknown
            }} =
             Matter.Native.Wire.error(%{
               "code" => "commissioning_failed",
               "sdk_status" => 0xF1230001,
               "effect" => "unknown"
             })
  end

  defp session(response) do
    {:ok, session} =
      Matter.connect(client: TestClient, response: normalize_response(response), timeout: 5_000)

    session
  end

  defp normalize_response({:error, _} = response), do: response
  defp normalize_response(response), do: response
end
