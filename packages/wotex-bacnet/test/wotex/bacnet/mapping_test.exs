defmodule Wotex.BACnet.MappingTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.BACnet.{Mapping, TestClient, Transport}
  alias Wotex.Runtime.{Context, ExecutionContext, Request}
  @href "bacnet://123/2,7/85/0"
  @target "123"

  test "Form addresses are typed and extensions survive mapping" do
    {:ok, form} = Wotex.Form.new(%{"href" => @href, "vendor:future" => %{"value" => 1}})

    assert {:ok,
            %{
              target: @target,
              message: %{object_type: 2, instance: 7, property: 85, array_index: 0}
            } = mapping} = Mapping.command(form, :readproperty, nil)

    assert mapping.form["vendor:future"] == %{"value" => 1}

    assert {:ok, %{message: %{property: 85, array_index: nil}}} =
             Mapping.command(form, :readproperty, nil, "bacnet://123/2,7")

    assert {:ok, _} = Mapping.command(form, :readproperty, nil, "bacnet://123/2,7/85")

    for href <- ["bacnet://123/2,7/85/0/1", "bacnet://123/2,7/x"],
        do: assert(match?({:error, _}, Mapping.command(form, :readproperty, nil, href)))

    assert {:error, _} = Mapping.command(form, :observeproperty, nil)
    assert {:error, _} = Mapping.command(nil, :readproperty, nil)

    for href <- [
          "invalid://wrong/path",
          @href <> "#fragment",
          "relative",
          "X",
          :binary.copy("x", 4097)
        ] do
      assert {:error, _} = Mapping.command(form, :readproperty, nil, href)
    end

    {:ok, write_form} =
      Wotex.Form.new(
        Map.put(Wotex.Form.to_map(form), "bacv:hasDataType", %{"@type" => "bacv:Null"})
      )

    assert {:ok, %{message: %{value: %{type: :null, value: nil}}}} =
             Mapping.command(write_form, :writeproperty, nil)

    assert {:error, _} = Mapping.command(form, :writeproperty, nil)
  end

  test "Runtime exact target matching, finite budgets and cleanup" do
    {:ok, form} = Wotex.Form.new(%{"href" => @href})
    {:ok, context} = Context.new(request_id: "test-1")
    execution = ExecutionContext.new(context, nil)

    request = %Request{
      operation: :readproperty,
      affordance_type: :property,
      affordance_name: "value",
      form: form,
      resolved_href: @href,
      profile: nil,
      request_id: "test-1",
      deadline: nil,
      input: nil
    }

    opts = [client: TestClient, target: @target]

    for deadline <- [
          nil,
          System.monotonic_time(:millisecond) + 1000,
          DateTime.add(DateTime.utc_now(), 1)
        ] do
      assert {:ok, _} = Transport.request(%{request | deadline: deadline}, execution, opts)
      assert_receive :disconnected
    end

    for deadline <- [
          :invalid,
          System.monotonic_time(:millisecond) - 1,
          DateTime.add(DateTime.utc_now(), -1)
        ],
        do:
          assert(
            match?({:error, _}, Transport.request(%{request | deadline: deadline}, execution, opts))
          )

    assert {:error, _} = Transport.request(request, execution, Keyword.put(opts, :timeout, 0))
    assert {:error, _} = Transport.request(request, execution, Keyword.put(opts, :target, "wrong"))
    assert {:error, _} = Transport.request(request, execution, [:bad])

    assert {:error, _} =
             Transport.request(request, ExecutionContext.new(context, "credential"), opts)

    assert {:error, _} = Transport.request(request, execution, Keyword.put(opts, :mode, :error))
    assert_receive :disconnected
    assert {:error, _} = Transport.subscribe(nil, nil, nil, nil)
    assert {:error, _} = Transport.unsubscribe(nil, nil, nil, nil)
  end
end
