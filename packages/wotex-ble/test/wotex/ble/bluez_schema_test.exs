defmodule Wotex.BLE.BlueZSchemaTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Wotex.BLE.BlueZ.{Frame, Options, Response}
  alias Wotex.BLE.Error

  defp response(result),
    do: %{"version" => 1, "id" => "request-1", "ok" => true, "result" => result}

  defp characteristic do
    %{
      "service_uuid" => "180f",
      "characteristic_uuid" => "2a19",
      "service_path" => "/service",
      "object_path" => "/char",
      "handle" => nil,
      "flags" => ["read"],
      "generation" => 1
    }
  end

  test "WBL-C07 strict ready/result schemas and finite error mapping" do
    opened = %{
      "generation" => 1,
      "device_path" => "/device",
      "link_owned" => false,
      "sender" => ":1.2"
    }

    assert {:ok, ^opened} = Response.parse(response(opened), "open")

    for changes <- [
          %{"generation" => 0},
          %{"device_path" => "not/a/path"},
          %{"sender" => "bluez"},
          %{"sender" => String.duplicate("x", 129)},
          %{"link_owned" => nil},
          %{"foreign" => nil}
        ] do
      assert :invalid = Response.parse(response(Map.merge(opened, changes)), "open")
    end

    for code <-
          ~w(invalid_options invalid_peer disconnected owner_changed not_permitted not_authorized not_supported busy invalid_value_length invalid_offset improperly_configured remote_error object_limit peer_not_found ambiguous_peer invalid_response invalid_characteristic peer_changed generation_exhausted snapshot_unstable timeout services_unresolved stale_discovery invalid_cursor cursor_limit transport_error) do
      frame = %{"version" => 1, "id" => "id", "ok" => false, "error" => %{"code" => code}}
      assert {:error, %Error{} = error} = Response.parse(frame, "discover")
      assert Atom.to_string(error.code) == code
      assert {:error, %Error{}} = Response.parse(put_in(frame, ["error", "status"], 1), "discover")
    end

    for error <- [
          %{"code" => "alien"},
          %{"code" => "timeout", "leak" => "secret"},
          %{"code" => "timeout", "status" => "wrong"},
          [],
          nil
        ] do
      assert :invalid =
               Response.parse(
                 %{"version" => 1, "id" => "id", "ok" => false, "error" => error},
                 "discover"
               )
    end

    assert {:ok, nil} = Response.parse(response(nil), "close")
    assert :invalid = Response.parse(response(nil), "discover")
    assert :invalid = Response.parse(%{}, "open")
  end

  test "WBL-N01 typed discovery pages reject mismatched generations, fields and ordering" do
    page = %{"generation" => 1, "characteristics" => [characteristic()], "cursor" => nil}

    assert {:ok, %{generation: 1, cursor: nil, characteristics: [_]}} =
             Response.parse(response(page), "discover")

    cursor = String.duplicate("a", 32)

    assert {:ok, %{cursor: ^cursor}} =
             Response.parse(response(%{page | "cursor" => cursor}), "discover")

    for change <- [
          %{"generation" => 0},
          %{"generation" => 2},
          %{"cursor" => "bad"},
          %{"cursor" => 1},
          %{"characteristics" => [characteristic(), characteristic()]},
          %{"characteristics" => List.duplicate(characteristic(), 65)},
          %{"characteristics" => [%{"generation" => 1}]},
          %{"characteristics" => [Map.put(characteristic(), "flags", [nil])]},
          %{"characteristics" => [Map.put(Map.delete(characteristic(), "flags"), "other", [])]}
        ] do
      assert :invalid = Response.parse(response(Map.merge(page, change)), "discover")
    end

    items = [Map.put(characteristic(), "object_path", "/z"), characteristic()]
    assert :invalid = Response.parse(response(%{page | "characteristics" => items}), "discover")
  end

  test "WBL-C02 explicit native options reject ambiguity before process acquisition" do
    peer = %{adapter: "/adapter", address: "00:11:22:33:44:55", address_type: :public}
    options = [peer: peer, bus_address: "unix:path=/tmp/bus", executable: "/usr/bin/python3"]
    assert {:ok, %{timeout: 5000, parameters: %{"connection" => "borrowed"}}} = Options.new(options)
    assert {:ok, _} = Options.new(Keyword.put(options, :bus_address, "unix:abstract=private-bus"))

    for invalid <- [
          nil,
          :bad,
          %{},
          [1],
          [{:peer, peer} | :improper],
          [{:peer, peer} | options],
          [{:unexpected, true} | options],
          Keyword.put(options, :owner, nil),
          Keyword.put(options, :connection, :auto),
          Keyword.put(options, :timeout, 0),
          Keyword.put(options, :timeout, 60_001),
          Keyword.put(options, :executable, "python"),
          Keyword.put(options, :executable, String.duplicate("/", 4097)),
          Keyword.put(options, :bus_address, "tcp:host=remote"),
          Keyword.put(options, :bus_address, "unix:path=/tmp/x;unix:path=/tmp/y")
        ] do
      assert {:error, %Error{code: :invalid_options}} = Options.new(invalid)
    end

    for invalid <- [
          nil,
          [limit: 0],
          [limit: true],
          [cursor: "short"],
          [limit: 1, limit: 2],
          [foreign: 1]
        ] do
      assert {:error, %Error{code: :invalid_options}} = Options.discovery(invalid)
    end
  end

  test "WBL-C07 line, node, depth and duplicate-key bounds" do
    assert {:ok, %{"list" => [1, true, nil, "a"], "float" => 1.2}} =
             Frame.decode(~s({"list":[1,true,null,"a"],"float":1.2}))

    for invalid <- [
          nil,
          <<255>>,
          "[",
          "[]",
          "null",
          ~s({"x":1,"x":2}),
          String.duplicate("x", 131_072),
          Jason.encode!(%{"x" => List.duplicate(1, 1025)}),
          Jason.encode!(Map.new(1..1025, &{Integer.to_string(&1), 1})),
          Jason.encode!(%{"x" => List.duplicate(List.duplicate(1, 1024), 4)}),
          Enum.reduce(1..9, "0", fn _, acc -> "{\"x\":" <> acc <> "}" end)
        ] do
      assert :error = Frame.decode(invalid)
    end
  end

  property "WBL-C02 WBL-C07 arbitrary bytes never raise at native pure boundaries" do
    check all(input <- binary(max_length: 600)) do
      assert Frame.decode(input) == :error or match?({:ok, %{}}, Frame.decode(input))
      assert match?({:error, %Error{}}, Options.discovery(cursor: input)) or byte_size(input) == 32
    end
  end
end
