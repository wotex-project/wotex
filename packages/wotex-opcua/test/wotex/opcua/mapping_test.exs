defmodule Wotex.OPCUA.MappingTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.OPCUA.{Mapping, TestClient, Transport}
  alias Wotex.Runtime.{Context, ExecutionContext, Request}
  @href "opc.tcp://localhost:4840/?id=ns%3D2%3Bs%3Dx%3By"
  @target "opc.tcp://localhost:4840/"

  test "Form addresses are typed and extensions survive mapping" do
    {:ok, form} = Wotex.Form.new(%{"href" => @href, "vendor:future" => %{"value" => 1}})

    assert {:ok,
            %{
              target: @target,
              message: %{
                node_id: %Wotex.OPCUA.Address{namespace: 2, kind: :string, identifier: "x;y"}
              }
            } = mapping} = Mapping.command(form, :readproperty, nil)

    assert mapping.form["vendor:future"] == %{"value" => 1}
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
      Wotex.Form.new(Map.put(Wotex.Form.to_map(form), "wotex:variantType", "String"))

    assert {:ok, %{message: %{value: %{type: "String", value: nil}}}} =
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
