defmodule Wotex.BACnet.RuntimeCOVMappingTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.BACnet.{COVOptions, COVRequest, Error, Mapping}
  alias Wotex.Form

  test "WBA-S05 WBA-V12 observation maps exact device and selector while retaining Form extensions" do
    input = %{
      "href" => "bacnet://123/1,7/85/0",
      "op" => ["observeproperty"],
      "vendor:future" => %{"nested" => [false, nil, 0]}
    }

    {:ok, form} = Form.new(input)
    assert {:ok, mapping} = Mapping.command(form, :observeproperty, nil)
    assert mapping.target == "123"

    assert mapping.message == %{
             type: :cov_property,
             object_type: 1,
             instance: 7,
             property: 85,
             array_index: 0,
             device_instance: 123
           }

    assert mapping.form == input
    assert Form.to_map(form) == input

    assert {:ok, %{message: %{property: 85, array_index: nil, device_instance: 124}}} =
             Mapping.command(form, :observeproperty, nil, "bacnet://124/1,7")

    assert {:error, %Error{code: :unsupported_operation}} =
             Mapping.command(form, :subscribeevent, nil)
  end

  test "WBA-S05 WBA-V12 COV configuration validates native fields without overriding association" do
    message = %{
      type: :cov_property,
      object_type: 1,
      instance: 7,
      property: 85,
      array_index: 0,
      device_instance: 123
    }

    assert {:ok, %COVRequest{} = request} = COVOptions.request(message, %{}, self())
    assert request.receiver == self() and request.confirmed and request.renew
    assert request.lifetime == 60 and request.max_queue_length == 1000

    options = %{
      confirmed: false,
      lifetime: 2,
      renew: false,
      max_queue_length: 1,
      duplicate_window_ms: 100,
      cov_increment: 1.5
    }

    assert {:ok, %COVRequest{} = request} = COVOptions.request(message, options, self())
    for {key, value} <- options, do: assert(Map.fetch!(request, key) == value)

    for options <- [
          nil,
          [],
          %{lifetime: 0},
          %{cov_increment: -1.0},
          %{confirmed: nil},
          %{type: :cov},
          %{object_type: 2},
          %{instance: 8},
          %{property: 77},
          %{array_index: 1},
          %{device_instance: 124},
          %{receiver: self()},
          %{arbitrary: "ignored?"}
        ] do
      assert {:error, %Error{effect: :none}} = COVOptions.request(message, options, self())
    end

    assert {:error, %Error{}} = COVOptions.request(%{}, %{}, self())
  end
end
