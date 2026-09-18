defmodule Wotex.CoAP.LinkFormat do
  @moduledoc """
  Decodes bounded RFC 6690 (August 2012) resource descriptions without resolving targets.

  Links preserve raw URI references and ordered attributes. A strict singleton
  policy rejects ambiguous descriptions; RFC 5988 first-occurrence attributes
  retain their first value. No description initiates I/O or authorizes a target.
  """

  alias Wotex.CoAP.Error
  alias Wotex.CoAP.LinkFormat.Attribute

  @limits %{max_body_bytes: 65_536, max_links: 256, max_attributes: 32, max_token_bytes: 1024}
  @type link :: %{href: binary(), attributes: [{binary(), binary() | true}]}

  @doc "Decodes a complete UTF-8 body under optionally lowered, unique D03 scanning limits."
  @spec decode(term(), term()) :: {:ok, [link()]} | {:error, Error.t()}
  def decode(body, options \\ []) do
    with {:ok, limits} <- options(options, %{}),
         :ok <- body(body, limits.max_body_bytes) do
      if body == "", do: {:ok, []}, else: links(body, limits, [], 0)
    end
  end

  defp options([], values), do: {:ok, Map.merge(@limits, values)}

  defp options([{key, value} | rest], values)
       when is_map_key(@limits, key) and not is_map_key(values, key) and is_integer(value) and
              value >= 1 do
    if value <= Map.fetch!(@limits, key),
      do: options(rest, Map.put(values, key, value)),
      else: failure(:invalid_link_options)
  end

  defp options(_, _), do: failure(:invalid_link_options)

  defp body(value, limit) when is_binary(value) do
    cond do
      byte_size(value) > limit -> limit(:body, limit)
      not String.valid?(value) -> failure(:invalid_link_format)
      controls?(value) -> failure(:invalid_link_format)
      true -> :ok
    end
  end

  defp body(_, _), do: failure(:invalid_link_format)
  defp controls?(<<>>), do: false
  defp controls?(<<byte, _::binary>>) when byte < 32 or byte == 127, do: true
  defp controls?(<<_, rest::binary>>), do: controls?(rest)

  defp links(_, limits, _, count) when count >= limits.max_links,
    do: limit(:links, limits.max_links)

  defp links(<<"<", rest::binary>>, limits, links, count) do
    with {:ok, href, rest} <- scan(rest, :uri, limits.max_token_bytes, [], 0),
         true <- Attribute.uri?(href),
         {:ok, attributes, rest} <- attributes(rest, limits, [], %{}, 0) do
      link = %{href: href, attributes: attributes}

      case rest do
        <<>> -> {:ok, Enum.reverse([link | links])}
        <<",", more::binary>> when more != "" -> links(more, limits, [link | links], count + 1)
        _ -> failure(:invalid_link_format)
      end
    else
      false -> failure(:invalid_link_format)
      error -> error
    end
  end

  defp links(_, _, _, _), do: failure(:invalid_link_format)

  defp attributes(<<";", _::binary>>, limits, _, _, count)
       when count >= limits.max_attributes,
       do: limit(:attributes, limits.max_attributes)

  defp attributes(<<";", rest::binary>>, limits, attributes, seen, count) do
    with {:ok, name, rest} <- scan(rest, :name, limits.max_token_bytes, [], 0),
         {:ok, value, quoted, rest} <- value(rest, limits.max_token_bytes),
         true <- Attribute.valid?(name, value, quoted),
         {:ok, attributes, seen} <- retain(name, value, attributes, seen) do
      attributes(rest, limits, attributes, seen, count + 1)
    else
      false -> failure(:invalid_link_format)
      error -> error
    end
  end

  defp attributes(rest, _, attributes, _, _), do: {:ok, Enum.reverse(attributes), rest}

  defp retain(name, value, attributes, seen) do
    key = String.downcase(name)
    repeated = Map.has_key?(seen, key)

    cond do
      key == "href" or (repeated and key in ~w(rt if sz anchor media type)) ->
        failure(:invalid_link_format)

      repeated and key in ~w(rel title title* obs) ->
        {:ok, attributes, seen}

      true ->
        value = if key == "obs", do: true, else: value
        {:ok, [{name, value} | attributes], Map.put(seen, key, true)}
    end
  end

  defp value(<<"=\"", rest::binary>>, limit) do
    with {:ok, value, rest} <- scan(rest, :quoted, limit, [], 0),
         do: {:ok, value, true, rest}
  end

  defp value(<<"=", rest::binary>>, limit) do
    with {:ok, value, rest} <- scan(rest, :token, limit, [], 0),
         do: {:ok, value, false, rest}
  end

  defp value(rest, _), do: {:ok, true, false, rest}

  defp scan(rest, mode, limit, bytes, count) do
    case next(rest, mode) do
      {:end, rest} ->
        value = IO.iodata_to_binary(Enum.reverse(bytes))
        {:ok, value, rest}

      {:byte, byte, size, rest} when count + size <= limit ->
        scan(rest, mode, limit, [byte | bytes], count + size)

      {:byte, _, _, _} ->
        limit(:token, limit)

      :error ->
        failure(:invalid_link_format)
    end
  end

  defp next(<<">", rest::binary>>, :uri), do: {:end, rest}
  defp next(<<"\"", rest::binary>>, :quoted), do: {:end, rest}

  defp next(<<"\\", byte, rest::binary>>, :quoted) when byte in 32..126,
    do: {:byte, byte, 2, rest}

  defp next(<<"\\", _::binary>>, :quoted), do: :error
  defp next(<<>>, mode) when mode in [:token, :name], do: {:end, <<>>}
  defp next(<<>>, _), do: :error

  defp next(<<byte, _::binary>> = rest, :name) when byte in [?;, ?,, ?=], do: {:end, rest}
  defp next(<<byte, _::binary>> = rest, :token) when byte in [?;, ?,], do: {:end, rest}
  defp next(<<byte, rest::binary>>, _), do: {:byte, byte, 1, rest}

  defp limit(field, value), do: {:error, Error.new(:link_limit, field, %{limit: value})}
  defp failure(code), do: {:error, Error.new(code)}
end
