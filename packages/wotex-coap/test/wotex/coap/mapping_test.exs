defmodule Wotex.CoAP.MappingTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.CoAP.{Mapping, Message, Transport}
  alias Wotex.Runtime.{Context, ExecutionContext, Request}

  test "content types, explicit methods, operations and extension preservation" do
    for {type, input, payload} <- [
          {"application/json", %{"value" => 7}, "{\"value\":7}"},
          {"application/octet-stream", <<255>>, <<255>>},
          {"text/plain;charset=utf-8", "text", "text"}
        ] do
      {:ok, form} =
        Wotex.Form.new(%{
          "href" => "coap://127.0.0.1/a?b=c",
          "contentType" => type,
          "vendor:note" => "preserve"
        })

      assert {:ok, mapping} = Mapping.command(form, :writeproperty, input)
      assert mapping.message.code == 3
      assert mapping.message.payload == payload
      assert mapping.form == form
      reply = %Message{type: :ack, code: 69, message_id: 1, payload: payload}
      assert {:ok, ^input} = Mapping.decode(mapping, reply)
      assert {:ok, nil} = Mapping.decode(mapping, %{reply | payload: <<>>})
      assert {:error, _} = Mapping.decode(mapping, %{reply | options: [{12, <<99>>}]})
      assert {:error, _} = Mapping.decode(mapping, %{reply | code: 128})
    end

    {:ok, form} = Wotex.Form.new(%{"href" => "coap://127.0.0.1/", "cov:method" => "POST"})
    assert {:ok, %{message: %{payload: "null"}}} = Mapping.command(form, :writeproperty, nil)

    assert {:error, %{code: :blockwise_not_supported}} =
             Mapping.decode(
               %{format: 42},
               %Message{
                 type: :ack,
                 code: 69,
                 message_id: 1,
                 payload: "part",
                 options: [{23, <<8>>}]
               }
             )

    assert {:ok, %{message: %{code: 2}}} = Mapping.command(form, :invokeaction, nil)

    assert {:error, _} =
             Mapping.decode(%{format: 50}, %Message{
               type: :ack,
               code: 69,
               message_id: 1,
               payload: "invalid"
             })

    assert {:error, _} =
             Mapping.decode(%{format: 0}, %Message{
               type: :ack,
               code: 69,
               message_id: 1,
               payload: <<255>>
             })

    for extra <- [
          %{"href" => "coaps://127.0.0.1/"},
          %{"cov:method" => "PATCH"},
          %{"cov:confirmable" => nil},
          %{"cov:contentFormat" => 99},
          %{"cov:accept" => -1},
          %{"contentType" => "unknown"},
          %{"op" => "invokeaction"}
        ] do
      {:ok, form} = Wotex.Form.new(Map.merge(%{"href" => "coap://127.0.0.1/"}, extra))
      assert {:error, _} = Mapping.command(form, :readproperty, nil)
    end

    for input <- [<<255>>, 123] do
      {:ok, form} =
        Wotex.Form.new(%{
          "href" => "coap://127.0.0.1/",
          "contentType" => "text/plain;charset=utf-8"
        })

      assert {:error, _} = Mapping.command(form, :writeproperty, input)
    end
  end

  test "Runtime deadline and credential failures happen before network access" do
    {:ok, form} = Wotex.Form.new(%{"href" => "coap://127.0.0.1/"})
    {:ok, context} = Context.new(request_id: "request-1")
    execution = ExecutionContext.new(context, nil)

    request = %Request{
      operation: :readproperty,
      affordance_type: :property,
      affordance_name: "value",
      form: form,
      resolved_href: Wotex.Form.href(form),
      profile: nil,
      request_id: "request-1",
      deadline: 0,
      input: nil
    }

    for deadline <- [
          System.monotonic_time(:millisecond) - 1,
          DateTime.add(DateTime.utc_now(), -1),
          :invalid
        ] do
      assert {:error, _} = Transport.request(%{request | deadline: deadline}, execution, [])
    end

    assert {:error, _} = Transport.request(request, ExecutionContext.new(context, "secret"), [])
    assert {:error, _} = Transport.subscribe(nil, nil, nil, nil)
    assert {:error, _} = Transport.unsubscribe(nil, nil, nil, nil)
  end
end
