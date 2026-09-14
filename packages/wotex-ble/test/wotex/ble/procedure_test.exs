defmodule Wotex.BLE.ProcedureTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Wotex.BLE
  alias Wotex.BLE.BlueZ.{Connection, Response}
  alias Wotex.BLE.{Error, Procedure, TestClient}

  defp envelope(value), do: %{"type" => "bytes", "base64" => Base.encode64(value)}

  test "WBL-P04 WBL-N01 codec options are finite and validated before client admission" do
    for type <-
          ~w(bytes utf8 boolean uint8 int8 uint16 int16 uint32 int32 uint64 int64 float32 float64)a,
        order <- [:little, :big] do
      assert {:ok, %{type: ^type, timeout: 5000, codec: [byte_order: ^order]}} =
               Procedure.options([value_type: type, byte_order: order], 5000)
    end

    for invalid <- [
          nil,
          [extra: true],
          [timeout: 1, timeout: 2],
          [timeout: 0],
          [timeout: 60_001],
          [{:timeout, 1} | :bad]
        ] do
      assert {:error, %Error{code: :invalid_options}} = Procedure.options(invalid, 5000)
    end

    for invalid <- [[value_type: :guess], [byte_order: :native]] do
      assert {:error, %Error{code: :invalid_value}} = Procedure.options(invalid, 5000)
    end

    assert {:error, %Error{code: :invalid_handle}} = Connection.request(nil, %{}, 1)
    assert {:error, %Error{code: :invalid_session}} = BLE.read(nil, %{})
    assert {:error, %Error{code: :invalid_session}} = BLE.write(nil, %{}, <<>>)
    assert {:error, %Error{code: :invalid_message}} = Procedure.parameters(nil)
  end

  test "WBL-C07 bytes envelopes and procedure results are exact" do
    for value <- [
          nil,
          %{},
          %{"type" => "bytes", "base64" => "!"},
          %{"type" => "bytes", "base64" => "Zh=="},
          %{"type" => "bytes", "base64" => "Zg"},
          envelope(:binary.copy(<<0>>, 513)),
          Map.put(envelope(<<1>>), "extra", true)
        ] do
      assert :invalid = Procedure.decode_bytes(value)
    end

    assert {:ok, "write",
            %{
              "value" => %{"type" => "bytes", "base64" => "AQ=="},
              "address" => %{"handle" => nil, "generation" => nil, "object_path" => nil}
            }} =
             Procedure.parameters(%{
               type: :write,
               service: "180f",
               characteristic: "2a19",
               value: <<1>>
             })

    assert {:ok, "read", %{"address" => _} = parameters} =
             Procedure.parameters(%{type: :read, service: "180f", characteristic: "2a19"})

    refute Map.has_key?(parameters, "value")
  end

  test "WBL-C07 named errors preserve only bounded identifiers" do
    frame = %{
      "version" => 1,
      "id" => "1",
      "ok" => false,
      "error" => %{"code" => "remote_error", "name" => "org.bluez.Error.FutureCase"}
    }

    assert {:error, %Error{details: %{dbus_name: "org.bluez.Error.FutureCase"}}} =
             Response.parse(frame, "write")

    assert {:error, %Error{details: %{dbus_name: "org.bluez.Error.FutureCase"}}} =
             Response.parse(put_in(frame["error"]["status"], 1), "write")

    for name <- [
          nil,
          "org.other.Error.Name",
          "org.bluez.Error.",
          "org.bluez.Error.bad-name",
          "org.bluez.Error.123",
          "org.bluez.Error.é",
          String.duplicate("x", 129)
        ] do
      assert :invalid = Response.parse(put_in(frame["error"]["name"], name), "write")
    end

    assert :invalid = Response.parse(put_in(frame["error"]["message"], "SECRET"), "write")
    assert :invalid = Response.parse(put_in(frame["error"]["code"], "future-code"), "write")
  end

  test "WBL-N01 explicit helpers reject incompatible custom-client success values" do
    assert {:error, %Error{code: :invalid_transport_return}} =
             BLE.connect(client: TestClient, mode: :connect_invalid)

    {:ok, session} = BLE.connect(client: TestClient)
    address = %{service: "180f", characteristic: "2a19"}
    assert {:error, %Error{code: :invalid_value}} = BLE.read(session, address)

    {:ok, invalid} = BLE.connect(client: TestClient, mode: :invalid)

    assert {:error, %Error{code: :invalid_transport_return}} =
             BLE.send(invalid, %{type: :read, service: "180f", characteristic: "2a19"})

    assert {:error, %Error{code: :invalid_transport_return, effect: :unknown}} =
             BLE.write(session, address, <<1>>)

    {:ok, failing} = BLE.connect(client: TestClient, mode: :typed)

    assert {:error, %Error{code: :remote_error, effect: :unknown}} =
             BLE.write(failing, address, <<1>>)
  end

  property "WBL-C07 bounded opaque bytes round-trip only through canonical base64" do
    check all(bytes <- binary(max_length: 512)) do
      encoded = envelope(bytes)
      assert {:ok, ^bytes} = Procedure.decode_bytes(encoded)
    end
  end
end
