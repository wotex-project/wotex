defmodule Wotex.Binding.MQTT.Test.RequestFactory do
  @moduledoc false

  alias Wotex.Binding.MQTT
  alias Wotex.Form
  alias Wotex.Runtime.{Context, ExecutionContext, Request}

  @spec request(atom(), keyword()) :: Request.t()
  def request(operation, opts \\ []) do
    form_map =
      Keyword.get(opts, :form, %{
        "href" => "mqtt://broker.example",
        "op" => Atom.to_string(operation),
        "mqv:topic" => "things/value"
      })

    {:ok, form} = Form.new(form_map)

    %Request{
      operation: operation,
      affordance_type: Keyword.get(opts, :affordance_type, :property),
      affordance_name: Keyword.get(opts, :affordance_name, "value"),
      form: form,
      resolved_href: Keyword.get(opts, :resolved_href, form_map["href"]),
      profile: MQTT.profile(),
      request_id: Keyword.get(opts, :request_id, "request-1"),
      deadline: Keyword.get(opts, :deadline),
      input: Keyword.get(opts, :input)
    }
  end

  @spec execution_context(term()) :: ExecutionContext.t()
  def execution_context(credential \\ :ephemeral_credential) do
    context = Context.new!(request_id: "request-1", deadline: 1_000)
    ExecutionContext.new(context, credential)
  end
end
