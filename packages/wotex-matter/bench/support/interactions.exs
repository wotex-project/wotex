defmodule Wotex.Matter.Bench.Interactions do
  @moduledoc false

  # Runtime requests for one Property read, one Property write and one Action
  # invocation of a Thing Description with `matter` Forms, selected through
  # both the one-shot and the controller binding profile.

  alias Wotex.Matter.Bench.Client
  alias Wotex.Runtime.{Context, ExecutionContext, FormSelector, Request}

  @on_off %{tag: :anonymous, type: :boolean, value: true}
  @setpoint %{tag: :anonymous, type: :i16, value: 2150}
  @empty %{tag: :anonymous, type: :structure, value: []}

  @interactions %{
    "readproperty" => {:property, "onOff", :readproperty, nil},
    "writeproperty" => {:property, "heatingSetpoint", :writeproperty, @setpoint},
    "invokeaction" => {:action, "toggle", :invokeaction, @empty}
  }

  @spec inputs() :: %{String.t() => map()}
  def inputs do
    {:ok, td} = Wotex.ThingDescription.from_map(thing_description())
    {:ok, controller} = Wotex.Matter.profile(:controller)
    oneshot = Wotex.Matter.profile()
    context = Context.new!(request_id: "bench-request-1")

    Map.new(@interactions, fn {label, {type, name, operation, input}} ->
      {label,
       %{
         oneshot: request(td, type, name, operation, oneshot, context, input),
         controller: request(td, type, name, operation, controller, context, input),
         execution: ExecutionContext.new(context, nil)
       }}
    end)
  end

  @spec config() :: keyword()
  def config, do: [client: Client, target: "1", timeout: 5_000, read_value: @on_off]

  @spec failing_config() :: keyword()
  def failing_config, do: Keyword.put(config(), :failure, :transport_unavailable)

  defp request(td, type, name, operation, profile, context, input) do
    {:ok, selection} = FormSelector.select(td, type, name, operation, [profile])
    Request.from_selection(selection, context, input)
  end

  defp thing_description do
    %{
      "@context" => Wotex.td_context_1_1(),
      "id" => "urn:example:matter:bridge",
      "title" => "Benchmark Matter node",
      "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
      "security" => "nosec_sc",
      "properties" => %{
        "onOff" => %{
          "type" => "boolean",
          "readOnly" => true,
          "forms" => [%{"href" => "matter://1/4660/1/6/0", "op" => "readproperty"}]
        },
        "heatingSetpoint" => %{
          "type" => "integer",
          "writeOnly" => true,
          "forms" => [%{"href" => "matter://1/4660/1/513/18", "op" => "writeproperty"}]
        }
      },
      "actions" => %{
        "toggle" => %{"forms" => [%{"href" => "matter://1/4660/1/6/2"}]}
      }
    }
  end
end
