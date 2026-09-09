defmodule Wotex.CoAP.Mapping do
  @moduledoc """
  Maps a W3C Web of Things Form to the package's dated CoAP profile.

  `command/4` selects the declared or default method, validates a `coap` or `coaps` href,
  converts JSON, UTF-8 text, or opaque binary input, and constructs a
  `Wotex.CoAP.Message`. The supported `cov:` terms are interpreted according to
  the draft baseline documented by the package. The original `Wotex.Form` is
  retained so unknown extension terms are not discarded.

  `decode/2` accepts successful CoAP response codes, verifies content format,
  and converts the payload without treating a remote error response as a
  Property value. Mapping is pure: it does not authorize an operation, resolve
  DNS, open a socket, or prove peer behavior. This module does not claim W3C
  binding-registry or Profile conformance.
  """

  alias Wotex.{CoAP, Form, JSON}
  alias Wotex.CoAP.{Codec, Error, Message}
  @methods %{"GET" => :get, "POST" => :post, "PUT" => :put, "DELETE" => :delete}
  @defaults %{
    readproperty: :get,
    writeproperty: :put,
    invokeaction: :post,
    observeproperty: :get,
    subscribeevent: :get
  }
  @contexts %{
    readproperty: :property,
    writeproperty: :property,
    invokeaction: :action,
    observeproperty: :property,
    subscribeevent: :event
  }
  @formats %{
    "application/json" => 50,
    "application/octet-stream" => 42,
    "text/plain;charset=utf-8" => 0
  }

  @doc "Maps one resolved Form to an endpoint, message and content format."
  @spec command(Form.t(), atom(), term(), binary() | nil) :: {:ok, map()} | {:error, term()}
  def command(form, op, input, resolved_href \\ nil)

  def command(%Form{value: map} = form, op, input, resolved_href)
      when map_size(form) == 2 and is_map(map) and
             (is_nil(resolved_href) or is_binary(resolved_href)) do
    with {:ok, context} <- Map.fetch(@contexts, op),
         {:ok, ^form} <- Form.new(map, for: context),
         true <- is_nil(input) or op in [:writeproperty, :invokeaction],
         {:ok, method} <- method(map, op),
         true <- Atom.to_string(op) in Form.operations(form, for: context),
         {:ok, uri} <- endpoint(resolved_href || Form.href(form)),
         {:ok, format} <- media_format(Map.get(map, "contentType", "application/json")),
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
         {:ok, message} <- options(message, map, format, op) do
      {:ok,
       %{
         host: uri.host,
         port: uri.port || default_port(uri.scheme),
         scheme: if(uri.scheme == "coaps", do: :coaps, else: :coap),
         message: message,
         format: format,
         form: form,
         operation: op,
         path: path
       }}
    else
      _ -> {:error, Error.new(:invalid_form)}
    end
  end

  def command(_, _, _, _), do: failure(:invalid_form)

  @doc "Decodes a complete validated representation, keeping empty bytes distinct from JSON null."
  @spec decode(map(), Message.t()) :: {:ok, term()} | {:error, Error.t()}
  def decode(%{format: format} = mapping, %Message{} = reply) when format in [0, 42, 50] do
    with :ok <- Codec.validate_options(reply),
         true <- byte_size(reply.payload) <= 1_048_576 do
      decode_valid(mapping, reply)
    else
      false -> failure(:body_limit)
      error -> error
    end
  end

  def decode(_, _), do: failure(:invalid_response)

  defp decode_valid(mapping, reply) do
    cond do
      reply.code in 128..191 ->
        {:error, Error.new(:remote_response, nil, %{code: reply.code})}

      reply.code not in 64..94 ->
        failure(:invalid_response)

      Codec.option(reply, 23) != [] or Codec.option(reply, 27) != [] ->
        failure(:incomplete_response)

      not valid_format?(reply, mapping.format) ->
        failure(:content_format_mismatch)

      empty_ack?(mapping, reply) ->
        {:ok, nil}

      true ->
        decode_payload(reply.payload, mapping.format)
    end
  end

  defp valid_format?(reply, format) do
    case Codec.option(reply, 12) do
      [] -> true
      [value] -> :binary.decode_unsigned(value) == format
    end
  end

  defp empty_ack?(%{operation: operation}, %{payload: <<>>, code: code} = reply),
    do:
      operation in [:writeproperty, :invokeaction] and code in [65, 66, 68] and
        Codec.option(reply, 12) == []

  defp empty_ack?(_, _), do: false

  defp endpoint(value) do
    with {:ok, uri} <- URI.new(value),
         true <-
           uri.scheme in ["coap", "coaps"] and is_binary(uri.host) and uri.host != "" and
             is_nil(uri.userinfo) and is_nil(uri.fragment) and
             (is_nil(uri.port) or uri.port in 1..65_535),
         do: {:ok, uri},
         else: (_ -> failure(:invalid_form))
  end

  defp media_format(value) when is_binary(value), do: Map.fetch(@formats, String.downcase(value))
  defp media_format(_), do: :error

  defp default_port("coaps"), do: 5684
  defp default_port("coap"), do: 5683

  defp method(map, op) do
    with {:ok, default} <- Map.fetch(@defaults, op) do
      case Map.fetch(map, "cov:method") do
        :error ->
          {:ok, default}

        {:ok, name} ->
          with {:ok, method} <- Map.fetch(@methods, name),
               true <- op not in [:observeproperty, :subscribeevent] or method == :get,
               do: {:ok, method},
               else: (_ -> :error)
      end
    end
  end

  defp encode_input(nil, _, method) when method in [:get, :delete], do: {:ok, <<>>}
  defp encode_input(value, format, _), do: encode(value, format)
  defp encode(value, 50), do: JSON.encode(value)
  defp encode(value, 42) when is_binary(value), do: {:ok, value}

  defp encode(value, 0) when is_binary(value) do
    if String.valid?(value), do: {:ok, value}, else: :error
  end

  defp encode(_, _), do: :error

  defp options(message, map, format, operation) do
    accept = Map.get(map, "cov:accept", format)
    content = Map.get(map, "cov:contentFormat", format)

    if accept == format and content == format do
      options = [{17, Codec.uint(accept)} | message.options]

      options =
        if operation in [:observeproperty, :subscribeevent],
          do: [{6, <<>>} | options],
          else: options

      message = %{message | options: options}
      with {:ok, _} <- Codec.encode(%{message | payload: <<>>}), do: {:ok, message}
    else
      :error
    end
  end

  defp decode_payload(payload, 50) do
    case JSON.decode(payload) do
      {:ok, value} -> {:ok, value}
      {:error, _} -> failure(:invalid_payload)
    end
  end

  defp decode_payload(payload, 0) do
    if String.valid?(payload), do: {:ok, payload}, else: {:error, Error.new(:invalid_payload)}
  end

  defp decode_payload(payload, 42), do: {:ok, payload}
  defp failure(code), do: {:error, Error.new(code)}
end
