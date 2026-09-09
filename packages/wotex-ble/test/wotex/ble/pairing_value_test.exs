defmodule Wotex.BLE.PairingValueTest do
  @moduledoc false

  @behaviour Wotex.BLE.Agent

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Wotex.BLE.BlueZ.{Pairing, Response}
  alias Wotex.BLE.{Challenge, Error}
  @impl Wotex.BLE.Agent
  def decide(_, _), do: :reject

  defp challenge(kind, value) do
    %{
      id: "challenge-1",
      peer: %{adapter: "/adapter", address: "00:11:22:33:44:55", address_type: :public},
      kind: kind,
      value: value,
      deadline_ms: -100
    }
  end

  test "WBL-P03 WBL-S02 WBL-V06 exact prompt types and normalization" do
    prompts = [
      {:request_pin, nil},
      {:request_passkey, nil},
      {:authorize_pairing, nil},
      {:confirm_passkey, 0},
      {:confirm_passkey, 999_999},
      {:display_passkey, %{passkey: 0, entered: 0}},
      {:display_passkey, %{passkey: 999_999, entered: 6}},
      {:display_pin, "000042"},
      {:authorize_service, "180F"}
    ]

    for {kind, value} <- prompts do
      assert {:ok, %Challenge{} = prompt} = Challenge.new(challenge(kind, value))
      assert {:ok, ^prompt} = Challenge.new(prompt)

      if kind == :authorize_service,
        do: assert(prompt.value == "0000180f-0000-1000-8000-00805f9b34fb")

      assert {:ok, %{"action" => "reject"}} = Pairing.decision(prompt, :reject)
    end

    {:ok, secret} = Challenge.new(challenge(:display_pin, "PIN_SECRET_42"))
    refute inspect(secret) =~ "PIN_SECRET_42"
    refute inspect(secret) =~ "00:11:22:33:44:55"
  end

  test "WBL-C02 forged prompts reject extra, missing and incompatible values" do
    for invalid <- [
          nil,
          %{},
          Map.put(challenge(:request_pin, nil), :extra, true),
          Map.put(challenge(:request_pin, nil), :id, ""),
          Map.put(challenge(:request_pin, nil), :id, String.duplicate("x", 65)),
          Map.put(challenge(:request_pin, nil), :id, <<0>>),
          Map.put(challenge(:request_pin, nil), :peer, %{}),
          Map.put(challenge(:request_pin, nil), :deadline_ms, nil),
          Map.put(challenge(:request_pin, nil), :deadline_ms, 0x8000_0000_0000_0000),
          challenge(:unknown, nil),
          challenge(:confirm_passkey, -1),
          challenge(:confirm_passkey, true),
          challenge(:confirm_passkey, 1_000_000),
          challenge(:request_pin, "hidden"),
          challenge(:display_pin, <<255>>),
          challenge(:display_pin, String.duplicate("x", 17)),
          challenge(:display_passkey, %{passkey: 1, entered: 7}),
          challenge(:display_passkey, %{passkey: 1, entered: 1, extra: true}),
          challenge(:authorize_service, "wrong")
        ] do
      assert {:error, %Error{code: :invalid_challenge}} = Challenge.new(invalid)
    end

    {:ok, valid} = Challenge.new(challenge(:request_pin, nil))
    assert {:error, %Error{code: :invalid_challenge}} = Challenge.new(Map.put(valid, :extra, 1))
    assert {:error, %Error{code: :invalid_challenge}} = Pairing.decision(%{}, :accept)
  end

  test "WBL-V06 each decision matches only its requested kind" do
    for kind <- [
          :confirm_passkey,
          :authorize_pairing,
          :authorize_service,
          :display_passkey,
          :display_pin
        ] do
      value =
        case kind do
          :confirm_passkey -> 42
          :authorize_service -> "180f"
          :display_passkey -> %{passkey: 42, entered: 1}
          :display_pin -> "000042"
          _ -> nil
        end

      assert {:ok, %{"action" => "accept"}} = Pairing.decision(challenge(kind, value), :accept)

      assert {:error, %Error{code: :pairing_rejected}} =
               Pairing.decision(challenge(kind, value), {:passkey, 42})
    end

    for value <- [0, 999_999] do
      assert {:ok, %{"action" => "passkey", "value" => ^value}} =
               Pairing.decision(challenge(:request_passkey, nil), {:passkey, value})
    end

    for value <- ["0", String.duplicate("x", 16)] do
      assert {:ok, %{"action" => "pin", "value" => ^value}} =
               Pairing.decision(challenge(:request_pin, nil), {:pin, value})
    end

    for {kind, decision} <- [
          {:request_pin, :accept},
          {:request_passkey, :accept},
          {:request_passkey, {:pin, "42"}},
          {:request_pin, {:passkey, 42}},
          {:request_pin, {:pin, ""}},
          {:request_pin, {:pin, <<0>>}},
          {:request_pin, {:pin, String.duplicate("x", 17)}},
          {:request_passkey, {:passkey, 1_000_000}},
          {:request_passkey, {:passkey, true}},
          {:request_pin, :wrong}
        ] do
      assert {:error, %Error{code: :pairing_rejected}} =
               Pairing.decision(challenge(kind, nil), decision)
    end
  end

  test "WBL-S02 policy is explicit, bounded and kept outside native parameters" do
    for {capability, native} <- [
          {:no_input_no_output, "NoInputNoOutput"},
          {:display_yes_no, "DisplayYesNo"},
          {:keyboard_only, "KeyboardOnly"}
        ] do
      assert {:ok, %{module: __MODULE__, config: :secret, capability: ^native, timeout: 5000}} =
               Pairing.options(%{capability: capability, agent: {__MODULE__, :secret}}, 5000)
    end

    for invalid <- [
          nil,
          %{},
          %{capability: :automatic, agent: {__MODULE__, nil}},
          %{capability: :keyboard_only, agent: {:erlang, nil}},
          %{capability: :keyboard_only, agent: {__MODULE__, nil}, extra: true},
          %{capability: :keyboard_only, agent: {__MODULE__, nil}, timeout: 60_001},
          %{capability: :keyboard_only, agent: {nil, nil}}
        ] do
      assert {:error, %Error{code: :invalid_options}} = Pairing.options(invalid, 5000)
    end
  end

  test "WBL-S05 challenge frames bind exact peer and convert only remaining time" do
    peer = %{"adapter" => "/adapter", "address" => "00:11:22:33:44:55", "address_type" => "public"}

    wire = %{
      "id" => "challenge-1",
      "peer" => peer,
      "kind" => "display_passkey",
      "value" => %{"passkey" => 42, "entered" => 2},
      "timeout_ms" => 50
    }

    assert {:ok, %Challenge{value: %{passkey: 42, entered: 2}, deadline_ms: -150}} =
             Pairing.challenge(wire, peer, -100, -200)

    assert {:ok, %Challenge{deadline_ms: -175}} = Pairing.challenge(wire, peer, -175, -200)

    assert {:ok, %Challenge{peer: %{address_type: :random}}} =
             Pairing.challenge(
               %{wire | "peer" => %{peer | "address_type" => "random"}},
               %{peer | "address_type" => "random"},
               200,
               0
             )

    for invalid <- [
          nil,
          Map.put(wire, "extra", true),
          %{wire | "peer" => %{peer | "address" => "11:22:33:44:55:66"}},
          %{wire | "kind" => "unknown"},
          %{wire | "value" => %{"passkey" => 42}},
          %{wire | "timeout_ms" => 0},
          %{wire | "timeout_ms" => 60_001}
        ] do
      assert {:error, %Error{code: :invalid_challenge}} = Pairing.challenge(invalid, peer, 100, 0)
    end

    assert {:error, %Error{code: :invalid_challenge}} = Pairing.challenge(wire, peer, 100, 100)
    invalid_peer = %{peer | "address_type" => "unknown"}

    assert {:error, %Error{code: :invalid_challenge}} =
             Pairing.challenge(%{wire | "peer" => invalid_peer}, invalid_peer, 100, 0)
  end

  test "WBL-C07 Pair results cannot infer success from arbitrary truthy payloads" do
    frame = %{"version" => 1, "id" => "1", "ok" => true, "result" => %{"paired" => true}}
    assert {:ok, %{paired: true}} = Response.parse(frame, "pair")

    for result <- [%{"paired" => false}, %{"paired" => true, "extra" => 1}, true, nil] do
      assert :invalid = Response.parse(%{frame | "result" => result}, "pair")
    end

    assert {:ok, nil} = Response.parse(%{frame | "result" => nil}, "agent_reply")
  end

  property "WBL-C02 arbitrary prompt bytes remain total and redacted" do
    check all(bytes <- binary(max_length: 80)) do
      result = Challenge.new(challenge(:display_pin, bytes))
      assert match?({:ok, %Challenge{}}, result) or match?({:error, %Error{}}, result)
    end
  end
end
