defmodule Wotex.CoAP.NativeCommandEncoderTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.CoAP.{Native.Command, Native.Wire, Security}

  @maximum_counter 0xFFFFFFFFFFFFFFFF

  test "WCO-N03 encodes every exact operation with monotonic decimal identities" do
    state = command_state()
    security = security()

    operations = [
      {:open, %{host: "127.0.0.1", port: 5683, generation: 17, security: security}},
      {:body_begin,
       %{
         body_id: "body",
         length: 3,
         sha256: "b5d4045c3f466fa91fe2cc6abe79232a1a57cdf104f7a26e716e0a1e2789df78"
       }},
      {:body_chunk, %{body_id: "body", offset: 0, data: "ABC"}},
      {:body_end, %{body_id: "body"}},
      {:request,
       %{
         method: :post,
         path: "/value?q=a+b",
         confirmable: false,
         accept: 0,
         content_format: 65_535,
         body_id: "body"
       }},
      {:observe, %{path: "/value", confirmable: true, observation_kind: :property, renew: false}},
      {:credit, %{generation: 17, ack_seq: 0}},
      {:cancel, %{subscription_id: "6", generation: 17}},
      {:close, %{}}
    ]

    {_, frames} =
      operations
      |> Enum.with_index(1)
      |> Enum.reduce({state, []}, fn {{operation, parameters}, expected}, {current, frames} ->
        assert {:ok, id, line, next} = Command.encode(current, operation, parameters, 60_000)
        assert id == Integer.to_string(expected)
        assert byte_size(line) <= 131_072 and String.ends_with?(line, "\n")
        assert :binary.matches(line, "\n") |> length() == 1
        assert {:ok, frame} = Wire.line(line)
        assert map_size(frame) == 5
        assert frame["id"] == id and frame["operation"] == Atom.to_string(operation)
        assert frame["timeout_ms"] == 60_000 and is_map(frame["parameters"])
        {next, [frame | frames]}
      end)

    frames = Enum.reverse(frames)
    open = hd(frames)["parameters"]
    assert open["security"]["master_secret"] == bytes(security.master_secret)
    assert open["security"]["id_context"] == nil
    assert Enum.at(frames, 2)["parameters"]["data"] == bytes("ABC")
    refute Map.has_key?(Enum.at(frames, 5)["parameters"], "accept")
  end

  test "WCO-N03 absent optional request fields are omitted rather than encoded as null" do
    state = command_state()

    request = %{
      method: :get,
      path: "/value",
      confirmable: true,
      accept: nil,
      content_format: nil,
      body_id: nil
    }

    assert {:ok, "1", line, state} = Command.encode(state, :request, request, 1)
    assert {:ok, %{"parameters" => parameters}} = Wire.line(line)
    assert parameters == %{"method" => "GET", "path" => "/value", "confirmable" => true}

    observe = %{
      path: "/value",
      confirmable: false,
      observation_kind: :event,
      renew: true,
      accept: nil
    }

    assert {:ok, "2", line, _} = Command.encode(state, :observe, observe, 1)
    assert {:ok, %{"parameters" => parameters}} = Wire.line(line)
    refute Map.has_key?(parameters, "accept")
  end

  test "WCO-N03 maximum body chunk and scalar boundaries remain within one line" do
    state = command_state()
    chunk = :binary.copy(<<255>>, 32_768)

    assert {:ok, _, line, state} =
             Command.encode(
               state,
               :body_chunk,
               %{body_id: String.duplicate("x", 64), offset: 1_048_576, data: chunk},
               60_000
             )

    assert byte_size(line) < 131_072
    assert {:ok, %{"parameters" => %{"data" => encoded}}} = Wire.line(line)
    assert encoded == bytes(chunk)

    assert {:ok, _, _, _} =
             Command.encode(
               state,
               :credit,
               %{generation: 17, ack_seq: @maximum_counter},
               60_000
             )
  end

  test "WCO-N03 invalid commands do not allocate an identity or expose credentials" do
    state = command_state()
    private = String.duplicate("PRIVATE-NATIVE-COMMAND-CANARY", 2)
    {:ok, forged} = Security.new(%{credential() | master_secret: :binary.copy(<<1>>, 16)})
    forged = %{forged | master_secret: private}

    invalid = [
      {:open, %{host: "localhost", port: 5683, generation: 17, security: security()}},
      {:open, %{host: "127.0.0.1", port: 5683, generation: 18, security: security()}},
      {:open, %{host: "127.0.0.1", port: 5683, generation: 17, security: forged}},
      {:body_begin, %{body_id: "body", length: 0, sha256: String.duplicate("A", 64)}},
      {:body_chunk, %{body_id: "body", offset: 0, data: :binary.copy("x", 32_769)}},
      {:body_end, %{body_id: ""}},
      {:request, %{method: :patch, path: "/", confirmable: true}},
      {:request, %{method: :get, path: "/a/../b", confirmable: true}},
      {:observe, %{path: "/", confirmable: true, observation_kind: :property, renew: nil}},
      {:credit, %{generation: 18, ack_seq: 0}},
      {:cancel, %{subscription_id: "", generation: 17}},
      {:close, %{extra: true}}
    ]

    for {operation, parameters} <- invalid do
      assert :error = Command.encode(state, operation, parameters, 1000)
    end

    assert :error = Command.encode(state, :close, %{}, 0)
    assert :error = Command.encode(state, :unknown, %{}, 1000)
    assert {:ok, "1", _, _} = Command.encode(state, :close, %{}, 1000)
    refute inspect(state) =~ private
  end

  test "WCO-N03 the last uint64 identity is allocated once before exhaustion" do
    state = %{command_state() | next_id: @maximum_counter}
    assert {:ok, id, _, exhausted} = Command.encode(state, :close, %{}, 1)
    assert id == Integer.to_string(@maximum_counter)
    assert exhausted.next_id == :exhausted
    assert :exhausted = Command.encode(exhausted, :close, %{}, 1)
    assert :exhausted = Command.encode(exhausted, :open, :invalid, :invalid)
  end

  test "WCO-N03 malformed construction and parameter types fail closed" do
    assert :error = Command.new(0)
    assert :error = Command.new(@maximum_counter + 1)
    assert :error = Command.new(1.0)
    assert :error = Command.encode(:invalid, :close, %{}, 1)

    state = command_state()

    for {operation, parameters} <- [
          {:body_begin, %{body_id: "body", length: 0, sha256: nil}},
          {:body_chunk, %{body_id: "body", offset: 0.0, data: <<>>}},
          {:request, %{method: :get, path: "/", confirmable: 1}},
          {:request, %{method: :get, path: "/", confirmable: true, accept: 65_536}},
          {:observe, %{path: "/", confirmable: true, observation_kind: :value, renew: true}},
          {:credit, %{generation: 17, ack_seq: 0.0}},
          {:cancel, %{subscription_id: :subscription, generation: 17}}
        ] do
      assert :error = Command.encode(state, operation, parameters, 1)
    end
  end

  defp command_state do
    {:ok, state} = Command.new(17)
    state
  end

  defp security do
    {:ok, security} = Security.new(credential())
    security
  end

  defp credential do
    %{
      mode: :oscore,
      master_secret: <<0::128>>,
      master_salt: <<>>,
      sender_id: <<>>,
      recipient_id: <<1>>,
      context_store: "/fixture/context"
    }
  end

  defp bytes(value), do: %{"type" => "bytes", "base64" => Base.encode64(value)}
end
