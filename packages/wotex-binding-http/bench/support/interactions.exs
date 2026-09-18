defmodule Wotex.Binding.HTTP.Bench.Interactions do
  @moduledoc false

  # Runtime requests selected from one synthetic Thing Description with HTTP
  # Forms, JSON payloads of growing size and configurations around the
  # in-memory client. Identifiers use reserved example domains.

  alias Wotex.Binding.HTTP
  alias Wotex.Binding.HTTP.Bench.Client
  alias Wotex.Binding.HTTP.{Codec, Config, Response}
  alias Wotex.Runtime.{Context, ExecutionContext, FormSelector, Request}
  alias Wotex.ThingDescription

  @max_bytes 1_048_576

  @spec sizes() :: [{String.t(), pos_integer()}]
  def sizes, do: [{"1 member", 1}, {"16 members", 16}, {"256 members", 256}]

  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @spec payload(pos_integer()) :: map()
  def payload(count) do
    Map.new(1..count, fn index ->
      {"sensor-#{String.pad_leading(Integer.to_string(index), 3, "0")}",
       %{"value" => 20.0 + index / 10, "unit" => "Cel", "valid" => true}}
    end)
  end

  @spec json(term()) :: binary()
  def json(value) do
    {:ok, json} = Codec.encode(value, @max_bytes)
    json
  end

  @spec request(Wotex.Runtime.interaction_type(), String.t(), atom(), term()) :: Request.t()
  def request(type, name, operation, input) do
    {:ok, profile} = HTTP.profile()
    {:ok, selection} = FormSelector.select(thing_description(), type, name, operation, [profile])
    Request.from_selection(selection, context(), input)
  end

  @spec execution_context() :: ExecutionContext.t()
  def execution_context, do: ExecutionContext.new(context(), nil)

  @spec config(map(), keyword()) :: Config.t()
  def config(replies, options \\ []) do
    {:ok, config} =
      HTTP.config(
        [client: {Client, replies}, headers: [{"user-agent", "consumer-host"}]] ++ options
      )

    config
  end

  @spec response(100..599, [{String.t(), String.t()}], binary()) :: Response.t()
  def response(status, headers, body) do
    {:ok, response} = Response.new(status, headers, body)
    response
  end

  defp context, do: Context.new!(request_id: "bench-request-1")

  defp thing_description do
    {:ok, td} =
      ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:example:thing:http-bench",
        "title" => "HTTP benchmark Thing",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" => %{
          "state" => %{
            "type" => "object",
            "observable" => true,
            "forms" => [
              %{
                "href" => "https://thing.example/properties/state",
                "op" => ["readproperty", "writeproperty"],
                "contentType" => "application/json"
              },
              %{
                "href" => "https://thing.example/properties/state/changes",
                "op" => ["observeproperty", "unobserveproperty"],
                "contentType" => "application/json",
                "subprotocol" => "sse"
              }
            ]
          }
        },
        "actions" => %{
          "adjust" => %{
            "input" => %{"type" => "object"},
            "forms" => [
              %{
                "href" => "https://thing.example/actions/adjust",
                "op" => "invokeaction",
                "contentType" => "application/json",
                "htv:methodName" => "POST",
                "htv:headers" => [
                  %{"htv:fieldName" => "x-interaction", "htv:fieldValue" => "adjust"}
                ]
              }
            ]
          }
        },
        "events" => %{
          "overheated" => %{
            "data" => %{"type" => "object"},
            "forms" => [
              %{
                "href" => "https://thing.example/events/overheated",
                "op" => ["subscribeevent", "unsubscribeevent"],
                "contentType" => "application/json",
                "subprotocol" => "sse"
              }
            ]
          }
        }
      })

    td
  end
end
