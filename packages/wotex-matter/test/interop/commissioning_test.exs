defmodule Wotex.Matter.CommissioningInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter
  alias Wotex.Matter.{Error, Native, OnboardingMaterial}

  @moduletag :interop
  @moduletag :software

  setup_all do
    fixture =
      System.fetch_env!("WOTEX_MATTER_COMMISSIONING_FIXTURE")
      |> File.read!()
      |> Jason.decode!()

    {:ok, fixture: fixture}
  end

  test "commissions a trusted peer, establishes CASE and opens an enhanced window", %{
    fixture: fixture
  } do
    scenario = Map.fetch!(fixture, "trusted")

    with_session(scenario, fn session ->
      assert {:ok, %{case: :established}} =
               Matter.commission_on_network(session, commissioning_request(scenario))

      assert {:ok, %OnboardingMaterial{} = material} =
               Matter.open_commissioning_window(session, window_request(scenario))

      assert material.node_id == Map.fetch!(scenario, "node_id")
      assert material.expires_in_s == get_in(scenario, ["window", "timeout_s"])
      assert inspect(material) == "#Wotex.Matter.OnboardingMaterial<redacted>"
    end)
  end

  test "a valid but wrong setup PIN reaches a final SDK failure", %{fixture: fixture} do
    scenario = Map.fetch!(fixture, "wrong_pin")

    with_session(scenario, fn session ->
      assert_sdk_failure(
        Matter.commission_on_network(session, commissioning_request(scenario)),
        scenario
      )
    end)
  end

  test "an untrusted attestation chain reaches a final SDK failure", %{fixture: fixture} do
    scenario = Map.fetch!(fixture, "attestation_failure")

    with_session(scenario, fn session ->
      assert_sdk_failure(
        Matter.commission_on_network(session, commissioning_request(scenario)),
        scenario
      )
    end)
  end

  test "expired enhanced-window onboarding material reaches a final SDK failure", %{
    fixture: fixture
  } do
    scenario = Map.fetch!(fixture, "expired_window")

    with_session(scenario, fn session ->
      assert_sdk_failure(
        Matter.commission_on_network(session, commissioning_request(scenario)),
        scenario
      )
    end)
  end

  test "an operational peer enforces its AccessControl ACL", %{fixture: fixture} do
    scenario = Map.fetch!(fixture, "acl_denied")

    with_session(scenario, fn session ->
      assert {:error,
              %Error{
                code: :interaction_status,
                details: %{status: status},
                effect: :none
              }} = Matter.read_attribute(session, address(scenario))

      assert status == Map.fetch!(scenario, "expected_status")
    end)
  end

  defp with_session(scenario, operation) do
    assert {:ok, session} = Matter.connect(controller_options(Map.fetch!(scenario, "controller")))

    try do
      operation.(session)
    after
      assert :ok = Matter.disconnect(session)
    end
  end

  defp controller_options(controller) do
    [
      client: Native,
      executable: Map.fetch!(controller, "executable"),
      lifecycle: :persistent,
      storage_path: Map.fetch!(controller, "storage_path"),
      storage_mode: enum(controller, "storage_mode", [:create_new, :open_existing]),
      authority: enum(controller, "authority", [:generate_root, :stored]),
      vendor_id: Map.fetch!(controller, "vendor_id"),
      fabric_id: Map.fetch!(controller, "fabric_id"),
      controller_node_id: Map.fetch!(controller, "controller_node_id"),
      paa_trust_store: Map.fetch!(controller, "paa_trust_store"),
      timeout: Map.get(controller, "timeout", 60_000)
    ]
  end

  defp commissioning_request(scenario) do
    Map.take(scenario, ["node_id", "setup_pin", "discriminator", "timeout"])
    |> atomize_keys()
  end

  defp window_request(scenario) do
    window = Map.fetch!(scenario, "window")

    %{
      node_id: Map.fetch!(scenario, "node_id"),
      timeout_s: Map.fetch!(window, "timeout_s"),
      iteration_count: Map.fetch!(window, "iteration_count"),
      discriminator: Map.fetch!(window, "discriminator")
    }
  end

  defp address(scenario) do
    scenario
    |> Map.fetch!("address")
    |> Map.take(["fabric_id", "node_id", "endpoint", "cluster", "member"])
    |> atomize_keys()
  end

  defp atomize_keys(map) do
    Map.new(map, fn {key, value} -> {String.to_existing_atom(key), value} end)
  end

  defp enum(map, key, allowed) do
    value = Map.fetch!(map, key)

    Enum.find(allowed, fn candidate -> Atom.to_string(candidate) == value end) ||
      raise ArgumentError, "invalid #{key}"
  end

  defp assert_sdk_failure(result, scenario) do
    expected_code = enum(scenario, "expected_code", [:commissioning_failed, :timeout])

    assert {:error,
            %Error{
              code: ^expected_code,
              details: %{sdk_status: sdk_status},
              effect: effect
            }} = result

    assert sdk_status == Map.fetch!(scenario, "expected_sdk_status")
    assert effect == enum(scenario, "expected_effect", [:none, :unknown])
  end
end
