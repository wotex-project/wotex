defmodule WotexContinuum.AdmissionParityTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias WotexContinuum.{
    ActionIntent,
    ActionResult,
    CanonicalJSON,
    Codec,
    Delivery,
    Error,
    ExitReceipt,
    Failure,
    Limits,
    ObservationProposal
  }

  @invalid_utf8 [<<255>>, <<0xC0, 0xAF>>, <<0xED, 0xA0, 0x80>>, <<0xF0, 0x90>>]
  @payload_locations [
    :observation_value,
    :observation_quality,
    :action_input,
    :action_output,
    :failure_details,
    :action_failure_details,
    :delivery_failure_details,
    :exit_failure_details
  ]

  test "native payload keys and values reject every invalid UTF-8 form at safe paths" do
    for bytes <- @invalid_utf8,
        location <- @payload_locations,
        shape <- [:key, :value] do
      {payload, suffix} = invalid_payload(bytes, shape)
      {module, input, parent_path, registered?} = payload_case(location, payload)
      expected_path = parent_path <> suffix
      label = "#{location} #{shape} #{inspect(bytes)}"

      assert_utf8_error(module.from_map(input), expected_path, label)
      assert_utf8_error(module.new(input), expected_path, label)

      {_, valid_input, _, _} = payload_case(location, valid_payload(shape))
      assert {:ok, valid} = module.from_map(valid_input), label
      forged = forge_payload(location, valid, payload)

      assert_utf8_error(module.from_map(forged), expected_path, label)
      assert_utf8_error(module.new(forged), expected_path, label)

      if registered? do
        assert_utf8_error(WotexContinuum.to_map(forged), expected_path, label)
        assert_utf8_error(Codec.encode(forged), expected_path, label)
        assert_utf8_error(Codec.canonicalize(forged), expected_path, label)
      end
    end
  end

  test "canonical JSON rejects invalid object keys before constructing an unsafe path" do
    for bytes <- @invalid_utf8 do
      assert_utf8_error(CanonicalJSON.encode(%{bytes => true}), "/", inspect(bytes), :encode)

      assert_utf8_error(
        CanonicalJSON.encode(%{"safe" => %{bytes => true}}),
        "/safe",
        inspect(bytes),
        :encode
      )
    end
  end

  test "valid Unicode and empty keys survive every native payload route" do
    payload = %{"温度" => ["é", %{"" => "𝄞", "nordic" => "å"}]}

    for location <- @payload_locations do
      {module, input, _, registered?} = payload_case(location, payload)
      assert {:ok, value} = module.from_map(input), inspect(location)
      assert {:ok, ^value} = module.new(value), inspect(location)

      if registered? do
        assert {:ok, canonical} = Codec.canonicalize(value), inspect(location)
        assert {:ok, ^value} = Codec.decode(canonical), inspect(location)
      else
        assert {:ok, canonical} = CanonicalJSON.encode(module.to_map(value)), inspect(location)
        assert Jason.decode!(canonical)["details"] == payload
      end
    end
  end

  test "native construction and decoder source limits have an explicit split" do
    cases = [
      {String.duplicate("x", 64), [max_string_bytes: 32], :string_limit_exceeded},
      {Enum.to_list(1..17), [max_collection_size: 16], :collection_limit_exceeded},
      {%{"items" => Enum.to_list(1..20)}, [max_nodes: 16], :node_limit_exceeded}
    ]

    for {payload, options, core_code} <- cases do
      assert {:ok, intent} = ActionIntent.from_map(action_intent(payload))

      source =
        intent
        |> ActionIntent.to_map()
        |> Jason.encode!()

      assert {:ok, ^intent} = Codec.decode(source)

      assert {:error,
              %Error{
                code: :limit_exceeded,
                phase: :limits,
                path: path,
                details: %{core_code: ^core_code}
              }} = Codec.decode(source, options)

      assert is_binary(path)
    end
  end

  test "iodata byte length and lexical bounds win before decoding or allocation-heavy parsing" do
    valid_source =
      "ok"
      |> action_intent()
      |> ActionIntent.from_map()
      |> then(fn {:ok, intent} -> intent end)
      |> ActionIntent.to_map()
      |> Jason.encode!()

    over_limit_iodata = [valid_source, <<255>>]
    bytes = :erlang.iolist_size(over_limit_iodata)

    assert {:error,
            %Error{
              code: :limit_exceeded,
              phase: :limits,
              path: "/",
              details: %{
                bytes: ^bytes,
                max_bytes: max_bytes,
                core_code: :byte_limit_exceeded
              }
            }} = Codec.decode(over_limit_iodata, max_bytes: bytes - 1)

    assert max_bytes == bytes - 1

    assert {:error,
            %Error{
              code: :limit_exceeded,
              phase: :limits,
              details: %{core_code: :string_limit_exceeded}
            }} = Codec.decode(~s({"oversized":), max_string_bytes: 4)

    assert {:error,
            %Error{
              code: :limit_exceeded,
              phase: :limits,
              details: %{core_code: :depth_limit_exceeded}
            }} = Codec.decode(~s({"a":[[[), max_depth: 2)
  end

  test "native payloads retain the shared structural, UTF-8, and JSON-value boundary" do
    depth = Limits.max_depth()
    accepted = nested_lists(depth)
    rejected = nested_lists(depth + 1)

    assert {:ok, intent} = ActionIntent.from_map(action_intent(accepted))
    assert intent.input == accepted

    assert {:error, %Error{code: :limit_exceeded, phase: :limits}} =
             ActionIntent.from_map(action_intent(rejected))

    assert {:ok, finite} = ActionIntent.from_map(action_intent(1.25))
    assert finite.input == 1.25

    assert {:error, %Error{code: :invalid_json_value, path: "/input"}} =
             ActionIntent.from_map(action_intent(self()))
  end

  defp invalid_payload(bytes, :key), do: {%{"safe" => %{bytes => true}}, "/safe"}
  defp invalid_payload(bytes, :value), do: {%{"safe" => [bytes]}, "/safe/0"}

  defp valid_payload(:key), do: %{"safe" => %{"valid" => true}}
  defp valid_payload(:value), do: %{"safe" => ["valid"]}

  defp payload_case(:observation_value, payload) do
    {ObservationProposal, observation(payload, %{}), "/value", true}
  end

  defp payload_case(:observation_quality, payload) do
    {ObservationProposal, observation(42, payload), "/quality", true}
  end

  defp payload_case(:action_input, payload) do
    {ActionIntent, action_intent(payload), "/input", true}
  end

  defp payload_case(:action_output, payload) do
    {ActionResult, successful_result(payload), "/output", true}
  end

  defp payload_case(:failure_details, payload) do
    {Failure, failure(payload), "/details", false}
  end

  defp payload_case(:action_failure_details, payload) do
    {ActionResult, failed_result(payload), "/error/details", true}
  end

  defp payload_case(:delivery_failure_details, payload) do
    {Delivery, failed_delivery(payload), "/error/details", true}
  end

  defp payload_case(:exit_failure_details, payload) do
    {ExitReceipt, failed_exit(payload), "/error/details", true}
  end

  defp forge_payload(:observation_value, value, payload), do: %{value | value: payload}
  defp forge_payload(:observation_quality, value, payload), do: %{value | quality: payload}
  defp forge_payload(:action_input, value, payload), do: %{value | input: payload}
  defp forge_payload(:action_output, value, payload), do: %{value | output: payload}
  defp forge_payload(:failure_details, value, payload), do: %{value | details: payload}

  defp forge_payload(:action_failure_details, value, payload),
    do: %{value | error: %{value.error | details: payload}}

  defp forge_payload(:delivery_failure_details, value, payload),
    do: %{value | error: %{value.error | details: payload}}

  defp forge_payload(:exit_failure_details, value, payload),
    do: %{value | error: %{value.error | details: payload}}

  defp observation(value, quality) do
    %{
      proposal_id: "proposal-example",
      thing_id: "urn:example:thing:pump-7",
      affordance_type: :property,
      affordance_name: "level",
      value: value,
      observed_at: "2026-09-02T10:00:00Z",
      quality: quality,
      context: execution_scope()
    }
  end

  defp action_intent(input) do
    %{
      intent_id: "intent-example",
      thing_id: "urn:example:thing:pump-7",
      action_name: "setLevel",
      input: input,
      requested_at: "2026-09-02T10:00:00Z",
      idempotency_key: "set-level-example",
      context: execution_scope()
    }
  end

  defp successful_result(output) do
    %{
      result_id: "result-example",
      intent_id: "intent-example",
      status: :succeeded,
      output: output,
      completed_at: "2026-09-02T10:00:01Z",
      context: execution_scope()
    }
  end

  defp failed_result(details) do
    %{
      result_id: "result-example",
      intent_id: "intent-example",
      status: :failed,
      completed_at: "2026-09-02T10:00:01Z",
      error: failure(details),
      context: execution_scope()
    }
  end

  defp failed_delivery(details) do
    %{
      delivery_id: "delivery-example",
      item_kind: "action_intent",
      item_id: "intent-example",
      source: "edge-example",
      destination: "consumer-example",
      status: :failed,
      attempt: 1,
      emitted_at: "2026-09-02T10:00:00Z",
      error: failure(details)
    }
  end

  defp failed_exit(details) do
    %{
      receipt_id: "exit-example",
      subject_id: "worker-example",
      operation: :remove,
      status: :failed,
      requested_at: "2026-09-02T10:00:00Z",
      completed_at: "2026-09-02T10:00:01Z",
      error: failure(details)
    }
  end

  defp failure(details), do: %{code: "rejected", message: "example", details: details}

  defp execution_scope do
    %{
      execution_id: "exec-example",
      node_id: "edge-example",
      mode: %{deployment: :hybrid, connectivity: :connected},
      observed_at: "2026-09-02T10:00:00Z"
    }
  end

  defp nested_lists(levels), do: Enum.reduce(1..levels, nil, fn _, acc -> [acc] end)

  defp assert_utf8_error(result, path, label, phase \\ :validation) do
    assert {:error, %Error{} = error} = result, label
    assert error.code == :invalid_utf8, label
    assert error.phase == phase, label
    assert error.path == path, label
    assert String.valid?(error.path), label
  end
end
