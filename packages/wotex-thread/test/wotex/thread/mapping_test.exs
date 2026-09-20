defmodule Wotex.Thread.MappingTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Runtime.{Context, ExecutionContext, Request}
  alias Wotex.Thread.{Mapping, RuntimeClient, Transport}
  @href "thread+unix://mesh/state"
  @target "mesh"

  test "Form addresses are typed and extensions survive mapping" do
    {:ok, form} = Wotex.Form.new(%{"href" => @href, "vendor:future" => %{"value" => 1}})

    assert {:ok, %{target: @target, message: %{type: :state}} = mapping} =
             Mapping.command(form, :readproperty, nil)

    assert mapping.form["vendor:future"] == %{"value" => 1}
    assert {:error, _} = Mapping.command(form, :observeproperty, nil)
    assert {:error, _} = Mapping.command(nil, :readproperty, nil)

    for href <- [
          "invalid://wrong/path",
          @href <> "#fragment",
          "relative",
          "X",
          :binary.copy("x", 4097),
          "thread+unix://mesh/unknown"
        ] do
      assert {:error, _} = Mapping.command(form, :readproperty, nil, href)
    end
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
      profile: Wotex.Thread.profile(),
      request_id: "test-1",
      deadline: nil,
      input: nil
    }

    opts = [
      client: RuntimeClient,
      test_pid: self(),
      peer_reply: "disabled",
      target: @target
    ]

    for deadline <- [
          nil,
          System.monotonic_time(:millisecond) + 1000,
          DateTime.add(DateTime.utc_now(), 1)
        ] do
      request = %{request | deadline: deadline}
      execution = ExecutionContext.new(Context.new!(request_id: "test-1", deadline: deadline), nil)
      assert {:ok, _} = Transport.request(request, execution, opts)
      assert_receive {:runtime_client, :open, _}
      assert_receive {:runtime_client, :request, %{type: :state}, _}
      assert_receive {:runtime_client, :close}
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

    assert {:error, %Wotex.Thread.Error{code: :invalid_options}} =
             Transport.request(request, execution, [target: @target] ++ opts)

    assert {:error, _} =
             Transport.request(request, ExecutionContext.new(context, "credential"), opts)

    assert {:error, _} =
             Transport.request(
               request,
               execution,
               Keyword.put(opts, :peer_reply, {:error, :private})
             )

    assert_receive {:runtime_client, :open, _}
    assert_receive {:runtime_client, :request, %{type: :state}, _}
    assert_receive {:runtime_client, :close}
    assert {:error, _} = Transport.subscribe(nil, nil, nil, nil)
    assert {:error, _} = Transport.unsubscribe(nil, nil, nil, nil)
  end
end
