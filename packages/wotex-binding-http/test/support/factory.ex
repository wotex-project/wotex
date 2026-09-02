defmodule Wotex.Binding.HTTP.Test.Factory do
  @moduledoc false

  alias Wotex.Binding.HTTP
  alias Wotex.Runtime.{Context, Request, Selection}

  def config(overrides \\ %{}) do
    defaults = %{
      owner: self(),
      request_return: {:error, :not_configured},
      subscribe_return: {:error, :not_configured},
      close_return: :ok
    }

    {:ok, config} =
      HTTP.config(client: {Wotex.Binding.HTTP.Test.FakeClient, Map.merge(defaults, overrides)})

    config
  end

  def request(operation, input \\ nil, form_overrides \\ %{}, request_id \\ "request-1") do
    form_map =
      Map.merge(
        %{
          "href" => "https://thing.example/interactions/value",
          "op" => Atom.to_string(operation),
          "contentType" => "application/json"
        },
        form_overrides
      )

    {:ok, form} = Wotex.Form.new(form_map)
    {:ok, profile} = HTTP.profile()
    {:ok, context} = Context.new(request_id: request_id, deadline: 50_000)

    selection = %Selection{
      affordance_type: affordance_type(operation),
      affordance_name: "value",
      affordance: %{},
      operation: operation,
      form: form,
      resolved_href: form_map["href"],
      profile: profile,
      security: %{names: ["security"], definitions: %{}}
    }

    Request.from_selection(selection, context, input)
  end

  def context(credential \\ :credential) do
    {:ok, context} = Context.new(request_id: "request-1", deadline: 50_000)
    Wotex.Runtime.ExecutionContext.new(context, credential)
  end

  def response(status, body \\ "", headers \\ []) do
    {:ok, response} = Wotex.Binding.HTTP.Response.new(status, headers, body)
    response
  end

  defp affordance_type(operation)
       when operation in [:readproperty, :writeproperty, :observeproperty, :unobserveproperty],
       do: :property

  defp affordance_type(operation)
       when operation in [:invokeaction, :queryaction, :cancelaction],
       do: :action

  defp affordance_type(operation) when operation in [:subscribeevent, :unsubscribeevent],
    do: :event
end
