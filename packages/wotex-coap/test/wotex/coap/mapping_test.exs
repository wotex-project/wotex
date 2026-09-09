defmodule Wotex.CoAP.MappingTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.CoAP.{Codec, Error, Mapping, Message, Transport}
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

      if type == "application/json",
        do:
          assert(
            {:error, %Error{code: :invalid_payload}} =
              Mapping.decode(mapping, %{reply | payload: <<>>})
          ),
        else: assert({:ok, <<>>} = Mapping.decode(mapping, %{reply | payload: <<>>}))

      assert {:error, _} = Mapping.decode(mapping, %{reply | options: [{12, <<99>>}]})
      assert {:error, _} = Mapping.decode(mapping, %{reply | code: 128})
    end

    {:ok, form} = Wotex.Form.new(%{"href" => "coap://127.0.0.1/", "cov:method" => "POST"})
    assert {:ok, %{message: %{payload: "null"}}} = Mapping.command(form, :writeproperty, nil)

    assert {:error, %{code: :incomplete_response}} =
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

  test "WCO-S04 WCO-I03 stream mapping uses real Property and Event Form contexts" do
    for {operation, context, explicit} <- [
          {:observeproperty, :property, %{"op" => "observeproperty"}},
          {:subscribeevent, :event, %{}}
        ] do
      map =
        Map.merge(
          %{
            "href" => "./a%2Fb?x=a%26b&plus=a+b",
            "contentType" => "application/json",
            "cov:accept" => 50,
            "cov:contentFormat" => 50,
            "vendor:note" => %{"keep" => [false, 0, nil]}
          },
          explicit
        )

      {:ok, form} = Wotex.Form.new(map, for: context)
      href = "coap://127.0.0.1:5684/a%2Fb?x=a%26b&plus=a+b"
      assert {:ok, mapping} = Mapping.command(form, operation, nil, href)
      assert mapping.operation == operation and mapping.port == 5684
      assert mapping.form == form and Wotex.Form.to_map(mapping.form) == map
      assert mapping.message.code == 1 and mapping.message.payload == <<>>
      assert Codec.option(mapping.message, 11) == ["a/b"]
      assert Codec.option(mapping.message, 15) == ["x=a&b", "plus=a+b"]
      assert Codec.option(mapping.message, 17) == [<<50>>]

      for extra <- [%{"cov:method" => "POST"}, %{"cov:accept" => 0}, %{"cov:contentFormat" => 42}] do
        {:ok, bad} = Wotex.Form.new(Map.merge(map, extra), for: context)
        assert {:error, %Error{code: :invalid_form}} = Mapping.command(bad, operation, nil, href)
      end

      assert {:error, %Error{code: :invalid_form}} = Mapping.command(form, operation, true, href)
    end
  end

  test "WCO-C02 WCO-I03 forged Forms, routes and native JSON values remain structured failures" do
    {:ok, form} = Wotex.Form.new(%{"href" => "coap://127.0.0.1/x"})

    for bad <- [
          nil,
          %{},
          %{form | value: nil},
          %{form | value: %Wotex.Form{value: nil}},
          Map.delete(form, :value),
          Map.put(form, :extra, true),
          %{form | value: Map.put(form.value, "vendor:x", %URI{})}
        ] do
      assert {:error, %Error{code: :invalid_form}} = Mapping.command(bad, :readproperty, nil)
    end

    for route <- [:bad, 1, %URI{}, false, "coap://user@127.0.0.1/x", "coap://127.0.0.1/x#bad"] do
      assert {:error, %Error{code: :invalid_form}} =
               Mapping.command(form, :readproperty, nil, route)
    end

    for input <- [%URI{}, %{"nested" => %URI{}}, [true | nil], %{key: 1}, <<255>>, self()] do
      assert {:error, %Error{code: :invalid_form}} = Mapping.command(form, :writeproperty, input)
    end

    assert {:error, %Error{code: :invalid_form}} = Mapping.command(form, nil, nil)
    assert {:error, %Error{code: :invalid_form}} = Mapping.command(form, :readproperty, false)
  end

  test "WCO-I03 representations distinguish JSON null, false, empty collections, bytes and absent ACK" do
    reply = %Message{type: :ack, code: 69, message_id: 1, options: [{12, <<0, 50>>}]}

    for {payload, expected} <- [
          {"null", nil},
          {"false", false},
          {"0", 0},
          {"[]", []},
          {"\"\"", ""},
          {"{}", %{}}
        ] do
      assert {:ok, ^expected} = Mapping.decode(%{format: 50}, %{reply | payload: payload})
    end

    for payload <- [
          "",
          "{\"x\":1,\"x\":2}",
          "[",
          String.duplicate("[", 65) <> "0" <> String.duplicate("]", 65)
        ] do
      assert {:error, %Error{code: :invalid_payload}} =
               Mapping.decode(%{format: 50}, %{reply | payload: payload})
    end

    for format <- [0, 42] do
      assert {:ok, ""} = Mapping.decode(%{format: format}, %{reply | payload: "", options: []})
    end

    for code <- [65, 66, 68], operation <- [:writeproperty, :invokeaction] do
      assert {:ok, nil} =
               Mapping.decode(%{format: 50, operation: operation}, %{
                 reply
                 | code: code,
                   options: []
               })

      assert {:error, %Error{code: :invalid_payload}} =
               Mapping.decode(%{format: 50, operation: operation}, %{reply | code: code})
    end

    for invalid <- [
          nil,
          Map.delete(reply, :payload),
          Map.put(reply, :extra, true),
          %{reply | payload: nil},
          %{reply | options: [{12, <<50>>} | nil]}
        ] do
      assert {:error, %Error{}} = Mapping.decode(%{format: 50}, invalid)
    end

    assert {:error, %Error{}} = Mapping.decode(nil, reply)
    assert {:error, %Error{}} = Mapping.decode(%{format: 50}, %{reply | code: 95})

    assert {:error, %Error{code: :body_limit}} =
             Mapping.decode(%{format: 42}, %{
               reply
               | options: [],
                 payload: :binary.copy("x", 1_048_577)
             })
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
