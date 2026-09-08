defmodule Wotex.CoAP.Mapping do
  @moduledoc "Draft CoAP Form mapping with explicit content conversion and preserved extensions."

  alias Wotex.{CoAP, Form}
  alias Wotex.CoAP.{Codec, Error}
  @methods %{"GET" => :get, "POST" => :post, "PUT" => :put, "DELETE" => :delete}
  @defaults %{readproperty: :get, writeproperty: :put, invokeaction: :post}
  @formats %{
    "application/json" => 50,
    "application/octet-stream" => 42,
    "text/plain;charset=utf-8" => 0
  }

  @doc "Maps one resolved Form to an endpoint, message and content format."
  @spec command(Form.t(), atom(), term(), binary() | nil) :: {:ok, map()} | {:error, term()}
  def command(%Form{} = form, op, input, resolved_href \\ nil) do
    map = Form.to_map(form)
    context = if op == :invokeaction, do: :action, else: :property

    with {:ok, method} <- method(map, op),
         true <- Atom.to_string(op) in Form.operations(form, for: context),
         {:ok, uri} <- URI.new(resolved_href || Form.href(form)),
         true <-
           uri.scheme == "coap" and is_binary(uri.host) and is_nil(uri.userinfo) and
             is_nil(uri.fragment),
         {:ok, format} <- Map.fetch(@formats, Map.get(map, "contentType", "application/json")),
         true <- is_boolean(Map.get(map, "cov:confirmable", true)),
         {:ok, payload} <- encode_input(input, format, method),
         path = (uri.path || "/") <> if(uri.query, do: "?" <> uri.query, else: ""),
         {:ok, message} <-
           CoAP.message(%{
             method: method,
             path: path,
             payload: payload,
             confirmable: Map.get(map, "cov:confirmable", true),
             content_format: if(is_nil(input) and method in [:get, :delete], do: nil, else: format)
           }),
         {:ok, message} <- options(message, map, format) do
      {:ok, %{host: uri.host, port: uri.port || 5683, message: message, format: format, form: form}}
    else
      _ -> {:error, Error.new(:invalid_form)}
    end
  end

  @doc "Converts a successful response without treating remote error codes as values."
  @spec decode(map(), Wotex.CoAP.Message.t()) :: {:ok, term()} | {:error, Error.t()}
  def decode(mapping, %{code: code} = reply) when code in 64..95 do
    formats = Codec.option(reply, 12)

    cond do
      Codec.option(reply, 23) != [] or Codec.option(reply, 27) != [] ->
        {:error, Error.new(:blockwise_not_supported)}

      formats == [] or formats == [Codec.uint(mapping.format)] ->
        decode_payload(reply.payload, mapping.format)

      true ->
        {:error, Error.new(:content_format_mismatch)}
    end
  end

  def decode(_, %{code: code}), do: {:error, Error.new(:remote_response, nil, %{code: code})}

  defp method(map, op) do
    with {:ok, default} <- Map.fetch(@defaults, op) do
      case Map.fetch(map, "cov:method") do
        :error -> {:ok, default}
        {:ok, name} -> Map.fetch(@methods, name)
      end
    end
  end

  defp encode_input(nil, _, method) when method in [:get, :delete], do: {:ok, <<>>}
  defp encode_input(value, format, _), do: encode(value, format)
  defp encode(value, 50), do: Jason.encode(value)
  defp encode(value, 42) when is_binary(value), do: {:ok, value}

  defp encode(value, 0) when is_binary(value) do
    if String.valid?(value), do: {:ok, value}, else: :error
  end

  defp encode(_, _), do: :error

  defp options(message, map, format) do
    accept = Map.get(map, "cov:accept", format)
    content = Map.get(map, "cov:contentFormat", format)

    if is_integer(accept) and accept in 0..65_535 and content == format do
      message = %{message | options: [{17, Codec.uint(accept)} | message.options]}
      with {:ok, _} <- Codec.encode(%{message | payload: <<>>}), do: {:ok, message}
    else
      :error
    end
  end

  defp decode_payload(<<>>, _), do: {:ok, nil}

  defp decode_payload(payload, 50) do
    case Jason.decode(payload) do
      {:ok, value} -> {:ok, value}
      {:error, _} -> {:error, Error.new(:invalid_payload)}
    end
  end

  defp decode_payload(payload, 0) do
    if String.valid?(payload), do: {:ok, payload}, else: {:error, Error.new(:invalid_payload)}
  end

  defp decode_payload(payload, 42), do: {:ok, payload}
end
