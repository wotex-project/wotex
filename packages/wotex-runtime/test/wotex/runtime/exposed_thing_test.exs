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

  test "WRT.02-2 and WRT.03-9 dispatch every operation through its exact entry point" do
    context = Context.new!(request_id: "req-operation-matrix")

    affordance_operations = [
      {:readproperty, "temperature"},
      {:writeproperty, "temperature"},
      {:observeproperty, "temperature"},
      {:unobserveproperty, "temperature"},
      {:invokeaction, "calibrate"},
      {:queryaction, "calibrate"},
      {:cancelaction, "calibrate"},
      {:subscribeevent, "alarm"},
      {:unsubscribeevent, "alarm"}
    ]

    handlers =
      affordance_operations
      |> Map.new(fn {operation, name} ->
        {{operation, name}, fn input, received -> {operation, input, received.request_id} end}
      end)
      |> Map.merge(
        Map.new(Wotex.Runtime.thing_operations(), fn operation ->
          {operation, fn input, received -> {operation, input, received.request_id} end}
        end)
      )

    {:ok, exposed} = ExposedThing.new(TDFactory.thing_description(), handlers)

    for {operation, name} <- affordance_operations do
      assert ExposedThing.dispatch(exposed, operation, name, :input, context) ==
               {operation, :input, "req-operation-matrix"}

      assert {:error, %Error{code: :unsupported_operation}} =
               ExposedThing.dispatch_thing(exposed, operation, :input, context)
    end

    for operation <- Wotex.Runtime.thing_operations() do
      assert ExposedThing.dispatch_thing(exposed, operation, :input, context) ==
               {operation, :input, "req-operation-matrix"}

      assert {:error, %Error{code: :unsupported_operation}} =
               ExposedThing.dispatch(exposed, operation, "temperature", :input, context)
    end
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

  test "handler errors pass through and handler exceptions propagate from both entries" do
    td = TDFactory.thing_description()
    context = Context.new!(request_id: "req-handler")

    {:ok, error_exposed} =
      ExposedThing.new(td, %{
        {:readproperty, "temperature"} => fn _, _ -> {:error, :rejected} end,
        readallproperties: fn _, _ -> {:error, :rejected} end
      })

    assert ExposedThing.dispatch(error_exposed, :readproperty, "temperature", nil, context) ==
             {:error, :rejected}

    assert ExposedThing.dispatch_thing(error_exposed, :readallproperties, nil, context) ==
             {:error, :rejected}

    {:ok, raising_exposed} =
      ExposedThing.new(td, %{
        {:readproperty, "temperature"} => fn _, _ -> raise "handler failure" end,
        readallproperties: fn _, _ -> raise "handler failure" end
      })

    assert_raise RuntimeError, "handler failure", fn ->
      ExposedThing.dispatch(raising_exposed, :readproperty, "temperature", nil, context)
    end

    assert_raise RuntimeError, "handler failure", fn ->
      ExposedThing.dispatch_thing(raising_exposed, :readallproperties, nil, context)
    end

    {:ok, exiting_exposed} =
      ExposedThing.new(td, %{
        {:readproperty, "temperature"} => fn _, _ -> exit(:handler_failure) end,
        readallproperties: fn _, _ -> exit(:handler_failure) end
      })

    assert catch_exit(
             ExposedThing.dispatch(exiting_exposed, :readproperty, "temperature", nil, context)
           ) == :handler_failure

    assert catch_exit(
             ExposedThing.dispatch_thing(exiting_exposed, :readallproperties, nil, context)
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
        {:readproperty, "missing"} => callback,
        readallproperties: callback
      })

    assert {:error, %Error{code: :affordance_not_found}} =
             ExposedThing.dispatch(exposed, :readproperty, "missing", nil, context)

    assert {:error, %Error{code: :unsupported_operation}} =
             ExposedThing.dispatch(exposed, :readallproperties, "temperature", nil, context)

    assert {:error, %Error{code: :invalid_dispatch_input}} =
             ExposedThing.dispatch(exposed, :readproperty, "temperature", nil, %{})

    assert {:error, %Error{code: :unsupported_operation}} =
             ExposedThing.dispatch_thing(exposed, :readproperty, nil, context)

    {:ok, td_without_root_forms} =
      TDFactory.thing_description()
      |> Wotex.ThingDescription.to_map()
      |> Map.delete("forms")
      |> Wotex.ThingDescription.from_map()

    {:ok, undeclared} = ExposedThing.new(td_without_root_forms, %{readallproperties: callback})

    assert {:error, %Error{code: :thing_operation_not_found}} =
             ExposedThing.dispatch_thing(undeclared, :readallproperties, nil, context)

    refute_receive {:invoked, _input}
  end

  test "selected inbound Form, schema, and policy admission remain consumer-owned" do
    parent = self()

    handler = fn input, context ->
      send(parent, {:handled, input, context.metadata})
      :handled
    end

    td_without_read_form =
      TDFactory.thing_description()
      |> Wotex.ThingDescription.to_map()
      |> put_in(
        ["properties", "temperature", "forms"],
        [%{"href" => "properties/temperature", "op" => ["writeproperty"]}]
      )
      |> then(fn map ->
        {:ok, td} = Wotex.ThingDescription.from_map(map)
        td
      end)

    {:ok, no_form_admission} =
      ExposedThing.new(td_without_read_form, %{{:readproperty, "temperature"} => handler})

    context = Context.new!(request_id: "req-no-inbound-form")

    assert ExposedThing.dispatch(
             no_form_admission,
             :readproperty,
             "temperature",
             nil,
             context
           ) == :handled

    assert_receive {:handled, nil, %{}}

    {:ok, no_schema_admission} =
      ExposedThing.new(TDFactory.thing_description(), %{
        {:invokeaction, "calibrate"} => handler
      })

    context = Context.new!(request_id: "req-no-schema-admission")

    assert ExposedThing.dispatch(
             no_schema_admission,
             :invokeaction,
             "calibrate",
             "not-a-number",
             context
           ) == :handled

    assert_receive {:handled, "not-a-number", %{}}

    context =
      Context.new!(
        request_id: "req-no-policy-admission",
        metadata: %{"consumer_policy_decision" => "deny"}
      )

    assert ExposedThing.dispatch(
             no_form_admission,
             :readproperty,
             "temperature",
             nil,
             context
           ) == :handled

    assert_receive {:handled, nil, %{"consumer_policy_decision" => "deny"}}
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
        {:readproperty, "temperature"} => handler,
        readallproperties: handler
      })

    tasks =
      for input <- 1..8 do
        Task.async(fn ->
          context = Context.new!(request_id: "req-concurrent-#{input}")

          if rem(input, 2) == 1 do
            ExposedThing.dispatch(exposed, :readproperty, "temperature", input, context)
          else
            ExposedThing.dispatch_thing(exposed, :readallproperties, input, context)
          end
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
