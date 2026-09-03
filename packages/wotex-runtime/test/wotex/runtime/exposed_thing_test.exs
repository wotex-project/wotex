defmodule Wotex.Runtime.ExposedThingTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Runtime.{Context, Error, ExposedThing}
  alias Wotex.Runtime.Test.TDFactory

  setup do
    handlers = %{
      {:readproperty, "temperature"} => fn _input, context ->
        {:ok, {:temperature, context.request_id}}
      end,
      {:invokeaction, "calibrate"} => fn input, context ->
        {:ok, {:calibrated, input, context.request_id}}
      end,
      {:subscribeevent, "alarm"} => fn input, context ->
        {:ok, {:subscribed, input, context.request_id}}
      end
    }

    {:ok, exposed} = ExposedThing.new(TDFactory.thing_description(), handlers)
    %{exposed: exposed}
  end

  test "dispatches Property, Action, and Event handlers with input and context", %{exposed: exposed} do
    context = Context.new!(request_id: "req-dispatch")

    assert ExposedThing.dispatch(exposed, :readproperty, "temperature", nil, context) ==
             {:ok, {:temperature, "req-dispatch"}}

    assert ExposedThing.dispatch(exposed, :invokeaction, "calibrate", 0.4, context) ==
             {:ok, {:calibrated, 0.4, "req-dispatch"}}

    assert ExposedThing.dispatch(exposed, :subscribeevent, "alarm", self(), context) ==
             {:ok, {:subscribed, self(), "req-dispatch"}}

    assert %Wotex.ThingDescription{} = ExposedThing.thing_description(exposed)
  end

  test "returns stable errors for missing affordances, handlers, and invalid input", %{
    exposed: exposed
  } do
    context = Context.new!(request_id: "req-errors")

    assert {:error, %Error{code: :affordance_not_found}} =
             ExposedThing.dispatch(exposed, :readproperty, "missing", nil, context)

    assert {:error, %Error{code: :handler_not_found}} =
             ExposedThing.dispatch(exposed, :writeproperty, "temperature", 1, context)

    assert {:error, %Error{code: :unsupported_operation}} =
             ExposedThing.dispatch(exposed, :invented, "temperature", nil, context)

    assert {:error, %Error{code: :invalid_dispatch_input}} =
             ExposedThing.dispatch(exposed, :readproperty, :temperature, nil, context)

    assert {:error, %Error{code: :invalid_exposed_thing}} =
             ExposedThing.dispatch(%{}, :readproperty, "temperature", nil, context)
  end

  test "rejects malformed handler tables and construction inputs" do
    td = TDFactory.thing_description()

    assert {:error, %Error{code: :invalid_handler}} =
             ExposedThing.new(td, %{
               {:invented, "temperature"} => fn _input, _context -> :ok end
             })

    assert {:error, %Error{code: :invalid_handler}} =
             ExposedThing.new(td, %{{:readproperty, "temperature"} => fn _input -> :ok end})

    assert {:error, %Error{code: :invalid_exposed_thing}} = ExposedThing.new(%{}, %{})
  end

  test "handler errors pass through and handler exceptions propagate" do
    td = TDFactory.thing_description()
    context = Context.new!(request_id: "req-handler")

    {:ok, error_exposed} =
      ExposedThing.new(td, %{
        {:readproperty, "temperature"} => fn _input, _context -> {:error, :rejected} end
      })

    assert ExposedThing.dispatch(error_exposed, :readproperty, "temperature", nil, context) ==
             {:error, :rejected}

    {:ok, raising_exposed} =
      ExposedThing.new(td, %{
        {:readproperty, "temperature"} => fn _input, _context -> raise "handler failure" end
      })

    assert_raise RuntimeError, "handler failure", fn ->
      ExposedThing.dispatch(raising_exposed, :readproperty, "temperature", nil, context)
    end
  end
end
