Code.require_file("write_runtime_client.exs", __DIR__)

defmodule RuntimeWriteArchiveConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.{BLE, ThingDescription}
  alias Wotex.Runtime.{ConsumedThing, Context}
  @accepted %{write_mode: :without_response, evidence: :native_queue_accepted}

  test "command retains its request, exact encoded input and native queue status" do
    consumed = consumer(%{"wotex:bleWriteMode" => "without_response"}, @accepted)

    context =
      Context.new!(
        request_id: "archive:command",
        deadline: System.monotonic_time(:millisecond) + 2000
      )

    assert {:ok, %{request_id: "archive:command", payload: @accepted, status: :accepted}} =
             ConsumedThing.write_property(consumed, "output", <<1, 2>>, context)

    assert_receive {:client_open, opened}

    assert_receive {:client_request,
                    %{type: :write, write_mode: :without_response, value: <<1, 2>>}, budget}

    assert budget > 0 and budget <= opened and opened <= 2000
    assert_receive :client_closed
    refute_received {:client_request, _, _}
  end

  test "default and explicit response writes retain acknowledged results without mode substitution" do
    for fields <- [%{}, %{"wotex:bleWriteMode" => "with_response"}] do
      assert {:ok, %{payload: :written, status: :ok}} = write(consumer(fields, :written), "ack")
      assert_receive {:client_open, _}
      assert_receive {:client_request, message, _}
      assert message.type == :write and message.value == <<1, 2>>
      assert Map.get(message, :write_mode, :with_response) == :with_response
      assert_receive :client_closed
    end
  end

  test "write selector applicability and unknown values refuse before client acquisition" do
    for value <- [nil, true, "auto", "command"] do
      assert {:error, _} = write(consumer(%{"wotex:bleWriteMode" => value}, @accepted), "invalid")
      refute_received {:client_open, _}
    end

    for value <- ["with_response", "without_response"] do
      consumed = consumer(%{"wotex:bleWriteMode" => value}, <<42>>)

      assert {:error, _} =
               ConsumedThing.read_property(consumed, "output", Context.new!(request_id: "read"))

      refute_received {:client_open, _}
    end
  end

  test "null, acknowledged, malformed and widened evidence never settle a command" do
    for reply <- [
          nil,
          :written,
          %{},
          Map.put(@accepted, :ack, true),
          %{@accepted | evidence: :acknowledged}
        ] do
      assert {:error, %{class: :permanent}} =
               write(consumer(%{"wotex:bleWriteMode" => "without_response"}, reply), "bad")

      assert_receive {:client_open, _}
      assert_receive {:client_request, %{write_mode: :without_response}, _}
      assert_receive :client_closed
      refute_received {:client_request, _, _}
    end
  end

  test "independent consumer selections and caller deadlines do not leak across requests" do
    first = consumer(%{"wotex:bleWriteMode" => "without_response"}, @accepted)
    second = consumer(%{}, :written)

    for {consumed, id, payload, status} <- [
          {first, "first", @accepted, :accepted},
          {second, "second", :written, :ok},
          {first, "third", @accepted, :accepted}
        ] do
      assert {:ok, %{request_id: ^id, payload: ^payload, status: ^status}} = write(consumed, id)
      assert_receive {:client_open, _}
      assert_receive {:client_request, _, _}
      assert_receive :client_closed
    end

    expired = Context.new!(request_id: "expired", deadline: System.monotonic_time(:millisecond) - 1)
    assert {:error, _} = ConsumedThing.write_property(first, "output", <<1, 2>>, expired)
    refute_received {:client_open, _}
  end

  defp write(consumed, id),
    do: ConsumedThing.write_property(consumed, "output", <<1, 2>>, Context.new!(request_id: id))

  defp consumer(fields, reply) do
    form = Map.put(fields, "href", "ble://peer/180f/2a19")

    {:ok, td} =
      ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "Archive write consumer",
        "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
        "security" => ["none"],
        "properties" => %{"output" => %{"forms" => [form]}}
      })

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [BLE.profile()],
        credentials: {ArchiveWriteCredentials, nil},
        transports: %{
          ble:
            {Wotex.BLE.Transport,
             [
               client: ArchiveWriteClient,
               receiver: self(),
               reply: reply,
               target: "peer",
               timeout: 2000
             ]}
        }
      )

    consumed
  end
end
