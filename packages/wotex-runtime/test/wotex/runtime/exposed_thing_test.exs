defmodule Wotex.Runtime.ExposedThingTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Runtime.{Context, Error, ExposedThing}
  alias Wotex.Runtime.Test.TDFactory

  setup do
    handlers = %{
      {:readproperty, "temperature"} => fn _, context ->
        {:ok, {:temperature, context.request_id}}
      end,
      {:invokeaction, "calibrate"} => fn input, context ->
        {:ok, {:calibrated, input, context.request_id}}
      end,
      {:subscribeevent, "alarm"} => fn input, context ->
        {:ok, {:subscribed, input, context.request_id}}
      end,
      readallproperties: fn _, context -> {:ok, {:all, context.request_id}} end
    }

    {:ok, exposed} = ExposedThing.new(TDFactory.thing_description(), handlers)
    %{exposed: exposed}
  end

  test "dispatches only declared Thing-level operation handlers", %{exposed: exposed} do
    context = Context.new!(request_id: "req-thing-dispatch")

    assert ExposedThing.dispatch_thing(exposed, :readallproperties, nil, context) ==
             {:ok, {:all, "req-thing-dispatch"}}

    assert {:error, %Error{code: :unsupported_operation}} =
             ExposedThing.dispatch_thing(exposed, :readproperty, nil, context)

    assert {:error, %Error{code: :handler_not_found}} =
             ExposedThing.dispatch_thing(exposed, :queryallactions, nil, context)

    {:ok, td_without_root_forms} =
      TDFactory.thing_description()
      |> Wotex.ThingDescription.to_map()
      |> Map.delete("forms")
      |> Wotex.ThingDescription.from_map()

    {:ok, undeclared} =
      ExposedThing.new(td_without_root_forms, %{
        readallproperties: fn _, _ -> :ok end
      })

    assert {:error, %Error{code: :thing_operation_not_found}} =
             ExposedThing.dispatch_thing(undeclared, :readallproperties, nil, context)
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

    assert {:error, %Error{code: :unsupported_operation}} =
             ExposedThing.dispatch(exposed, :readallproperties, "temperature", nil, context)

    assert {:error, %Error{code: :invalid_dispatch_input}} =
             ExposedThing.dispatch(exposed, :readproperty, :temperature, nil, context)

    assert {:error, %Error{code: :invalid_exposed_thing}} =
             ExposedThing.dispatch(%{}, :readproperty, "temperature", nil, context)
  end

  test "rejects malformed handler tables and construction inputs" do
    td = TDFactory.thing_description()

    assert {:error, %Error{code: :invalid_handler}} =
             ExposedThing.new(td, %{
               {:invented, "temperature"} => fn _, _ -> :ok end
             })

    assert {:error, %Error{code: :invalid_handler}} =
             ExposedThing.new(td, %{{:readproperty, "temperature"} => fn _ -> :ok end})

    assert {:error, %Error{code: :invalid_handler}} =
             ExposedThing.new(td, %{
               {:readallproperties, "temperature"} => fn _, _ -> :ok end
             })

    assert {:error, %Error{code: :invalid_exposed_thing}} = ExposedThing.new(%{}, %{})
  end

  test "handler errors pass through and handler exceptions propagate" do
    td = TDFactory.thing_description()
    context = Context.new!(request_id: "req-handler")

    {:ok, error_exposed} =
      ExposedThing.new(td, %{
        {:readproperty, "temperature"} => fn _, _ -> {:error, :rejected} end
      })

    assert ExposedThing.dispatch(error_exposed, :readproperty, "temperature", nil, context) ==
             {:error, :rejected}

    {:ok, raising_exposed} =
      ExposedThing.new(td, %{
        {:readproperty, "temperature"} => fn _, _ -> raise "handler failure" end
      })

    assert_raise RuntimeError, "handler failure", fn ->
      ExposedThing.dispatch(raising_exposed, :readproperty, "temperature", nil, context)
    end

    {:ok, exiting_exposed} =
      ExposedThing.new(td, %{
        {:readproperty, "temperature"} => fn _, _ -> exit(:handler_failure) end
      })

    assert catch_exit(
             ExposedThing.dispatch(exiting_exposed, :readproperty, "temperature", nil, context)
           ) == :handler_failure
  end

  test "invalid routes never invoke an available callback" do
    parent = self()
    context = Context.new!(request_id: "req-no-dispatch")

    callback = fn input, _ ->
      send(parent, {:invoked, input})
      :unexpected
    end

    {:ok, exposed} =
      ExposedThing.new(TDFactory.thing_description(), %{
        {:readproperty, "temperature"} => callback,
        readallproperties: callback
      })

    assert {:error, %Error{code: :affordance_not_found}} =
             ExposedThing.dispatch(exposed, :readproperty, "missing", nil, context)

    assert {:error, %Error{code: :unsupported_operation}} =
             ExposedThing.dispatch(exposed, :readallproperties, "temperature", nil, context)

    assert {:error, %Error{code: :invalid_dispatch_input}} =
             ExposedThing.dispatch(exposed, :readproperty, "temperature", nil, %{})

    refute_receive {:invoked, _input}
  end

  test "concurrent dispatch stays in each independent caller process" do
    parent = self()

    handler = fn input, context ->
      send(parent, {:started, self(), input, context.request_id})

      receive do
        {:release, ^input} -> {:ok, {input, context.request_id}}
      end
    end

    {:ok, exposed} =
      ExposedThing.new(TDFactory.thing_description(), %{
        {:readproperty, "temperature"} => handler
      })

    tasks =
      for input <- 1..8 do
        Task.async(fn ->
          context = Context.new!(request_id: "req-concurrent-#{input}")
          ExposedThing.dispatch(exposed, :readproperty, "temperature", input, context)
        end)
      end

    started =
      for _ <- 1..8 do
        assert_receive {:started, caller, input, "req-concurrent-" <> request_input}, 1_000
        assert Integer.to_string(input) == request_input
        {caller, input}
      end

    callers =
      started
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()

    assert length(callers) == 8
    Enum.each(started, fn {caller, input} -> send(caller, {:release, input}) end)

    assert tasks
           |> Enum.map(&Task.await(&1, 1_000))
           |> Enum.sort() ==
             Enum.map(1..8, &{:ok, {&1, "req-concurrent-#{&1}"}})
  end
end
