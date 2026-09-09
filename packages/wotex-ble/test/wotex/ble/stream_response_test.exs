defmodule Wotex.BLE.StreamResponseTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.BLE.BlueZ.{Response, Stream}
  alias Wotex.BLE.Error

  defp native_binding do
    %{
      "subscription_id" => "1",
      "generation" => 1,
      "characteristic" => %{
        "service_uuid" => "0000180f-0000-1000-8000-00805f9b34fb",
        "characteristic_uuid" => "00002a19-0000-1000-8000-00805f9b34fb",
        "service_path" => "/service",
        "object_path" => "/characteristic",
        "handle" => 1,
        "generation" => 1,
        "flags" => ["notify"]
      },
      "requested_mode" => "auto",
      "effective_mode" => "notify"
    }
  end

  defp frame(binding) do
    %{
      "version" => 1,
      "subscription_id" => binding["subscription_id"],
      "generation" => 1,
      "event" => "value",
      "value" => %{"type" => "bytes", "base64" => "AQ=="},
      "metadata" =>
        binding
        |> Map.take(["characteristic", "requested_mode", "effective_mode"])
        |> Map.put("source", "bluez_value_change")
    }
  end

  test "WBL-C07 S04 establishment binds all typed characteristic selectors and modes" do
    source = native_binding()
    assert {:ok, parsed} = Stream.establishment(source)

    params = %{
      "mode" => "auto",
      "address" => %{
        "service" => parsed.characteristic.service_uuid,
        "characteristic" => parsed.characteristic.characteristic_uuid,
        "handle" => 1,
        "object_path" => "/characteristic",
        "generation" => 1
      }
    }

    assert Stream.matches?(parsed, "1", params)
    refute Stream.matches?(parsed, "2", params)
    refute Stream.matches?(parsed, "1", %{params | "mode" => "notify"})

    for {key, wrong} <- [
          {"service", "other"},
          {"characteristic", "other"},
          {"handle", 2},
          {"generation", 2},
          {"object_path", "/other"}
        ] do
      refute Stream.matches?(parsed, "1", put_in(params["address"][key], wrong))
    end

    for malformed <- [
          nil,
          Map.put(source, "extra", true),
          Map.delete(source, "characteristic"),
          %{source | "generation" => 1.0},
          %{source | "subscription_id" => ""},
          %{source | "subscription_id" => String.duplicate("x", 65)},
          %{source | "requested_mode" => "unknown"},
          %{source | "requested_mode" => "bluez_selected"},
          %{source | "effective_mode" => "indicate"},
          %{source | "characteristic" => []},
          put_in(source["characteristic"]["extra"], true),
          put_in(source["characteristic"]["flags"], ["notify", "notify"]),
          %{
            source
            | "characteristic" =>
                Map.put(Map.delete(source["characteristic"], "handle"), "other", 1)
          }
        ] do
      assert :invalid = Stream.establishment(malformed)
    end
  end

  test "WBL-C07 V08 stream envelopes accept exact bytes and finite terminal failures" do
    source = native_binding()
    assert {:ok, parsed} = Stream.establishment(source)
    report = frame(source)
    assert {:ok, <<1>>, %{source: :bluez_value_change}} = Stream.report(report, parsed)
    assert {:ok, <<1>>, _} = Stream.report(report, nil)

    for malformed <- [
          nil,
          Map.put(report, "extra", true),
          %{report | "generation" => 2},
          %{report | "subscription_id" => "foreign"},
          %{report | "event" => "guess"},
          %{report | "metadata" => %{}},
          put_in(report["metadata"]["source"], "att_notification"),
          put_in(report["metadata"]["characteristic"]["object_path"], "/other"),
          put_in(report["value"]["base64"], "AQ"),
          put_in(report["value"]["base64"], Base.encode64(:binary.copy(<<1>>, 513)))
        ] do
      assert :invalid = Stream.report(malformed, parsed)
    end

    error = %{
      report
      | "event" => "error",
        "value" => nil,
        "metadata" => %{"error" => %{"code" => "subscription_lost"}}
    }

    assert {:error, %Error{code: :subscription_lost}} = Stream.report(error, parsed)
    assert :invalid = Stream.report(put_in(error["metadata"]["error"]["message"], "SECRET"), parsed)
    assert :invalid = Stream.report(put_in(error["metadata"]["error"]["code"], "unknown"), parsed)
    assert :invalid = Stream.report(%{error | "value" => false}, parsed)

    assert {:ok, nil} =
             Response.parse(
               %{"version" => 1, "id" => "2", "ok" => true, "result" => nil},
               "unsubscribe"
             )
  end

  property "WBL-C07 arbitrary stream byte envelopes are total and enforce 512 bytes" do
    assert {:ok, parsed} = Stream.establishment(native_binding())

    check all(bytes <- binary(max_length: 520)) do
      report = put_in(frame(native_binding())["value"]["base64"], Base.encode64(bytes))

      if byte_size(bytes) <= 512,
        do: assert(match?({:ok, ^bytes, _}, Stream.report(report, parsed))),
        else: assert(Stream.report(report, parsed) == :invalid)
    end
  end
end
