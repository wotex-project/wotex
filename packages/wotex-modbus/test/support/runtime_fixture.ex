defmodule Wotex.Modbus.RuntimeFixture do
  @moduledoc false

  import ExUnit.Assertions
  alias Wotex.{Form, Modbus, ThingDescription}
  alias Wotex.Modbus.{Error, RuntimeCredentials, RuntimeTransport, TestPeer}
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, Retry}

  @faults %{
    "read_timeout" => {:deadline_exceeded, :none},
    "pre_send_acquisition_failure" => {:connect_failed, :none},
    "admission_full" => {:busy, :none},
    "wrong_correlation" => {:response_mismatch, :none},
    "invalid_route" => {:invalid_href, :none},
    "sent_write_timeout" => {:deadline_exceeded, :unknown}
  }
  @operations %{"readproperty" => :readproperty, "writeproperty" => :writeproperty}
  @options %{
    "attempt" => :attempt,
    "max_attempts" => :max_attempts,
    "delay" => :delay,
    "idempotent?" => :idempotent?
  }

  @doc false
  @spec run(map()) :: map()
  def run(%{"operation" => operation, "input" => input}) do
    operation
    |> observe(input)
    |> Jason.encode!()
    |> Jason.decode!()
  end

  @doc false
  @spec td(map()) :: map()
  def td(form) do
    %{
      "@context" => "https://www.w3.org/2022/wot/td/v1.1",
      "title" => "Protocol fixture",
      "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
      "security" => ["none"],
      "properties" => %{"reading" => %{"forms" => [form]}}
    }
  end

  @doc false
  @spec consumed(map(), tuple(), term()) :: ConsumedThing.t()
  def consumed(td_map, transport, credential \\ nil) do
    {:ok, description} = ThingDescription.from_map(td_map)

    {:ok, consumed} =
      ConsumedThing.new(description,
        profiles: [Modbus.profile()],
        transports: %{modbus: transport},
        credentials: {RuntimeCredentials, credential}
      )

    consumed
  end

  defp observe("runtime_read", input) do
    assert input["profile_mode"] == "tcp"
    test = self()
    reply = Base.decode16!(input["peer_reply"]["hex"], case: :lower)
    assert input["peer_reply"]["kind"] == "modbus_pdu"
    assert input["peer_reply"]["echo_request_transaction_and_unit"]

    {peer, port} =
      TestPeer.start(fn _, unit, pdu ->
        send(test, {:runtime_wire, unit, pdu})
        reply
      end)

    affordance = input["affordance"]
    [source_form] = get_in(input, ["thing_description", "properties", affordance, "forms"])
    original_uri = URI.parse(source_form["href"])
    actual_href = URI.to_string(%{original_uri | port: port})

    td =
      put_in(input["thing_description"], ["properties", affordance, "forms"], [
        Map.put(source_form, "href", actual_href)
      ])

    consumed =
      consumed(
        td,
        {RuntimeTransport, {:record, test, [timeout: input["transport_options"]["timeout"]]}}
      )

    clock = input["clock"]
    assert clock["kind"] == "monotonic_ms"

    {:ok, context} =
      Context.new(
        request_id: input["request_id"],
        deadline: System.monotonic_time(:millisecond) + clock["deadline"] - clock["start"]
      )

    {:ok, result} = ConsumedThing.read_property(consumed, affordance, context)
    assert_receive {:runtime_request, request}
    assert_receive {:runtime_wire, unit, <<3, offset::16, quantity::16>>}
    assert_receive {:runtime_resources, resources}
    assert :ok = Task.await(peer)
    refute_received {:runtime_wire, _, _}
    observed_uri = URI.parse(request.resolved_href)

    %{
      profile_id: BindingProfile.id(request.profile),
      resolved_href: URI.to_string(%{observed_uri | port: original_uri.port}),
      command: %{
        function: :read_holding_registers,
        unit_id: unit,
        offset: offset,
        quantity: quantity
      },
      result: Map.from_struct(result),
      extension: Form.to_map(request.form)["example:extension"],
      request_count: 1,
      owned_resources_after: length(resources)
    }
  end

  defp observe("error_retry_projection", input) do
    {code, effect} = Map.fetch!(@faults, input["fault"])
    assert Atom.to_string(code) == input["native_error"]["code"]
    assert Atom.to_string(effect) == input["native_error"]["effect"]
    native_error = Error.with_effect(Error.new(code), effect)
    form = %{"href" => "modbus+tcp://127.0.0.1/1/1", "modv:entity" => "HoldingRegister"}
    consumed = consumed(td(form), {RuntimeTransport, {:fault, native_error}})
    operation = Map.fetch!(@operations, input["wot_operation"])
    {:ok, context} = Context.new(request_id: "fault")

    result =
      case operation do
        :readproperty -> ConsumedThing.read_property(consumed, "reading", context)
        :writeproperty -> ConsumedThing.write_property(consumed, "reading", 42, context)
      end

    {:error, error} = result

    options =
      Enum.map(input["retry_options"], fn {key, value} -> {Map.fetch!(@options, key), value} end)

    decision =
      case Retry.decision(operation, error, options) do
        {:retry, delay} -> %{retry: delay}
        :stop -> :stop
      end

    %{
      class: error.class,
      cause_code: error.details.cause.code,
      retained_native_effect: Map.has_key?(error.details.cause, :effect),
      retry_decision: decision
    }
  end
end
