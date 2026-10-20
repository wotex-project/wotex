defmodule Wotex.BLE.WriteModeTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.{BLE, Form, ThingDescription}
  alias Wotex.BLE.{Address, BlueZ, Error, Mapping, NativeFixture, Procedure}
  alias Wotex.BLE.BlueZ.Response
  alias Wotex.Runtime.{ConsumedThing, Context}

  @address %{service: "180f", characteristic: "2a19"}
  @accepted %{write_mode: :without_response, evidence: :native_queue_accepted}

  test "explicit modes and command evidence are closed before dispatch" do
    for options <- [
          [write_mode: nil],
          [write_mode: :auto],
          [write_mode: :without_response, write_mode: :without_response],
          [write_mode: :with_response, extra: true]
        ] do
      assert {:error, %Error{code: :invalid_options}} = Procedure.write_options(options, 1000)
    end

    assert {:ok, %{write_mode: :with_response}} = Procedure.write_options([], 1000)

    assert {:ok, %{write_mode: :without_response}} =
             Procedure.write_options([write_mode: :without_response], 1000)

    assert {:error, _} = Procedure.options([write_mode: :without_response], 1000)

    assert {:error, _} =
             Address.validate_message(
               Map.merge(@address, %{type: :read, write_mode: :without_response})
             )

    assert {:error, _} =
             Address.validate_message(
               Map.merge(@address, %{type: :write, value: <<>>, write_mode: :auto})
             )

    assert {:ok, "write_command", %{"address" => _, "value" => %{"base64" => "AQ=="}}} =
             Procedure.parameters(
               Map.merge(@address, %{type: :write, value: <<1>>, write_mode: :without_response})
             )

    envelope = %{
      "version" => 1,
      "id" => "1",
      "ok" => true,
      "result" => %{"write_mode" => "without_response", "evidence" => "native_queue_accepted"}
    }

    assert {:ok, @accepted} = Response.parse(envelope, "write_command")
    assert :invalid = Response.parse(envelope, "write")

    for value <- [
          nil,
          "written",
          %{},
          Map.put(envelope["result"], "ack", true),
          %{"write_mode" => "without_response", "evidence" => "acknowledged"}
        ] do
      assert :invalid = Response.parse(%{envelope | "result" => value}, "write_command")
    end
  end

  test "one-shot BlueZ refuses command mode without invoking its executable" do
    {:ok, session} =
      BLE.connect(
        client: BlueZ,
        executable: "/never-invoke-command",
        object_path: "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF/service0001/char0002",
        service: "180f",
        characteristic: "2a19"
      )

    assert {:error, %Error{code: :not_supported, effect: :none}} =
             BLE.write(session, @address, <<1>>, write_mode: :without_response)

    assert :ok = BLE.disconnect(session)
  end

  test "persistent command uses its own operation and never manufactures an acknowledged write" do
    {options, record} =
      NativeFixture.options(%{
        "flags" => ["read", "write", "write-without-response"],
        "characteristics" => 1
      })

    {:ok, session} = BLE.connect([client: BlueZ, lifecycle: :persistent] ++ options)
    on_exit(fn -> BLE.disconnect(session) end)
    assert {:ok, @accepted} = BLE.write(session, @address, <<1>>, write_mode: :without_response)
    assert {:ok, :written} = BLE.write(session, @address, <<2>>, write_mode: :with_response)

    operations =
      record
      |> NativeFixture.calls()
      |> Enum.map(& &1["operation"])
      |> Enum.reject(&is_nil/1)

    assert operations == ["open", "write_command", "write"]
    assert :ok = BLE.disconnect(session)
  end

  test "command loss after submission remains uncertain and never retries" do
    for mode <- [
          "procedure_blocked",
          "procedure_crash",
          "procedure_missing_event",
          "procedure_malformed"
        ] do
      {options, record} =
        NativeFixture.options(%{
          "flags" => ["write-without-response"],
          "characteristics" => 1,
          "modes" => [mode]
        })

      {:ok, session} = BLE.connect([client: BlueZ, lifecycle: :persistent] ++ options)
      on_exit(fn -> BLE.disconnect(session) end)

      assert {:error, %Error{effect: :unknown}} =
               BLE.write(session, @address, <<1>>, write_mode: :without_response, timeout: 100)

      assert Enum.count(NativeFixture.calls(record), &(&1["operation"] == "write_command")) == 1
    end
  end

  test "a queued command expires unsent while the active command retains uncertainty" do
    {options, record} =
      NativeFixture.options(%{
        "flags" => ["write-without-response"],
        "characteristics" => 1,
        "modes" => ["procedure_blocked"]
      })

    {:ok, session} = BLE.connect([client: BlueZ, lifecycle: :persistent] ++ options)

    active =
      Task.async(fn ->
        BLE.write(session, @address, <<1>>, write_mode: :without_response, timeout: 300)
      end)

    NativeFixture.eventually(fn ->
      Enum.any?(NativeFixture.calls(record), &Map.has_key?(&1, "submitted"))
    end)

    assert {:error, %Error{effect: :none}} =
             BLE.write(session, @address, <<2>>, write_mode: :without_response, timeout: 20)

    assert {:error, %Error{effect: :unknown}} = Task.await(active, 2000)
    assert Enum.count(NativeFixture.calls(record), &(&1["operation"] == "write_command")) == 1
  end

  test "write-only Form selector preserves command evidence through real Runtime" do
    fields = %{"href" => "ble://peer/180f/2a19", "wotex:bleWriteMode" => "without_response"}
    {:ok, form} = Form.new(fields, for: :property)

    assert {:ok, %{message: %{write_mode: :without_response}}} =
             Mapping.command(form, :writeproperty, <<1>>)

    assert {:error, %Error{code: :invalid_selector}} = Mapping.command(form, :readproperty, nil)
    {:ok, invalid} = Form.new(%{fields | "wotex:bleWriteMode" => "auto"}, for: :property)

    assert {:error, %Error{code: :invalid_selector}} =
             Mapping.command(invalid, :writeproperty, <<1>>)

    {options, record} =
      NativeFixture.options(%{"flags" => ["write-without-response"], "characteristics" => 1})

    {:ok, td} =
      ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "Command fixture",
        "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
        "security" => ["none"],
        "properties" => %{"output" => %{"forms" => [fields]}}
      })

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [BLE.profile()],
        credentials: {Wotex.BLE.RuntimeErrorPort, nil},
        transports: %{
          ble:
            {Wotex.BLE.Transport,
             [client: BlueZ, lifecycle: :persistent, target: "peer"] ++ options}
        }
      )

    assert {:ok, %{payload: @accepted, status: :accepted}} =
             ConsumedThing.write_property(
               consumed,
               "output",
               <<1>>,
               Context.new!(request_id: "command")
             )

    assert Enum.count(NativeFixture.calls(record), &(&1["operation"] == "write_command")) == 1
  end
end
