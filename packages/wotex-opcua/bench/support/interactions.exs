defmodule Wotex.OPCUA.Bench.Interactions do
  @moduledoc false

  # Runtime requests for a Property read and two Property writes of a Thing
  # Description with `opc.tcp` Forms, selected through the one-shot profile.

  alias Wotex.OPCUA.Bench.{Client, Values}
  alias Wotex.Runtime.{Context, ExecutionContext, FormSelector, Request}

  @endpoint "opc.tcp://plc.example:4840"

  @spec inputs() :: %{String.t() => map()}
  def inputs do
    {:ok, td} = Wotex.ThingDescription.from_map(thing_description())
    context = Context.new!(request_id: "bench-request-1")
    execution = ExecutionContext.new(context, nil)
    blocks = %{type: "ByteString", array: true, value: Values.byte_strings(16, 64)}

    %{
      "read Double" => input(td, "temperature", :readproperty, nil, context, execution),
      "write Double" => input(td, "setpoint", :writeproperty, 180.5, context, execution),
      "write ByteString array of 16 x 64 bytes" =>
        input(td, "calibration", :writeproperty, blocks, context, execution)
    }
  end

  @spec config() :: keyword()
  def config do
    [
      client: Client,
      target: @endpoint,
      timeout: 5_000,
      read_value: Values.native_data_value("Double", false, 21.5)
    ]
  end

  @spec failing_config() :: keyword()
  def failing_config, do: Keyword.put(config(), :failure, :connection_failed)

  defp input(td, name, operation, value, context, execution) do
    {:ok, selection} = FormSelector.select(td, :property, name, operation, [Wotex.OPCUA.profile()])
    %{request: Request.from_selection(selection, context, value), execution: execution}
  end

  defp thing_description do
    %{
      "@context" => Wotex.td_context_1_1(),
      "id" => "urn:example:opcua:oven",
      "title" => "Benchmark OPC UA oven",
      "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
      "security" => "nosec_sc",
      "properties" => %{
        "temperature" => property("number", "readproperty", "plant/line-4/oven-2/temperature"),
        "setpoint" =>
          "number"
          |> property("writeproperty", "plant/line-4/oven-2/setpoint")
          |> put_in(["forms", Access.at(0), "wotex:variantType"], "Double"),
        "calibration" => property("array", "writeproperty", "plant/line-4/oven-2/calibration")
      }
    }
  end

  defp property(type, operation, node) do
    %{
      "type" => type,
      "forms" => [
        %{"href" => "#{@endpoint}?id=ns%3D2%3Bs%3D#{URI.encode_www_form(node)}", "op" => operation}
      ]
    }
  end
end
