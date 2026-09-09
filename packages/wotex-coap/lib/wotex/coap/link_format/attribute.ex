defmodule Wotex.CoAP.LinkFormat.Attribute do
  @moduledoc false

  @name ~r/\A[A-Za-z0-9!#$&+.^_`|~-]+\*?\z/
  @token ~r/\A[A-Za-z0-9!#$%&'()*+.\/:<=>?@\[\]^_`{|}~-]+\z/
  @relation ~r/\A[a-z][a-z0-9.-]*\z/
  @cardinal ~r/\A(?:0|[1-9][0-9]*)\z/
  @media_type ~r/\A
    [A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,126}\/
    [A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,126}
    \z/x
  @language ~r/\A
    (?:[a-z]{2,3}(?:-[a-z]{3}){0,3}|[a-z]{4,8})
    (?:-[a-z]{4})?(?:-[a-z]{2}|-[0-9]{3})?
    (?:-[a-z0-9]{5,8}|-[0-9][a-z0-9]{3})*
    (?:-[a-wy-z0-9](?:-[a-z0-9]{2,8})+)*
    (?:-x(?:-[a-z0-9]{1,8})+)?\z/ix
  @private_language ~r/\Ax(?:-[a-z0-9]{1,8})+\z/i
  @grandfathered ~w(en-gb-oed i-ami i-bnn i-default i-enochian i-hak i-klingon i-lux
    i-mingo i-navajo i-pwn i-tao i-tay i-tsu sgn-be-fr sgn-be-nl sgn-ch-de art-lojban
    cel-gaulish no-bok no-nyn zh-guoyu zh-hakka zh-min zh-min-nan zh-xiang)

  @doc false
  @spec valid?(binary(), binary() | true, boolean()) :: boolean()
  def valid?(name, value, quoted) do
    Regex.match?(@name, name) and syntax?(String.downcase(name), value, quoted)
  end

  defp syntax?(name, value, quoted) when name in ~w(rel rev rt if),
    do: relations?(value, quoted)

  defp syntax?("anchor", value, true), do: uri?(value)
  defp syntax?("anchor", _, _), do: false
  defp syntax?("title", value, quoted), do: is_binary(value) and quoted
  defp syntax?("sz", value, false), do: is_binary(value) and Regex.match?(@cardinal, value)
  defp syntax?("sz", _, _), do: false
  defp syntax?("hreflang", value, false), do: is_binary(value) and language?(value)
  defp syntax?("hreflang", _, _), do: false
  defp syntax?("type", value, _), do: is_binary(value) and Regex.match?(@media_type, value)

  defp syntax?("ct", value, quoted),
    do: list?(value, quoted, &content_format?/1)

  defp syntax?("media", value, _) when is_binary(value),
    do: Regex.match?(~r/\A[A-Za-z][A-Za-z0-9-]*(?: *, *[A-Za-z][A-Za-z0-9-]*)*\z/, value)

  defp syntax?("media", _, _), do: false

  defp syntax?(name, value, quoted) do
    if String.ends_with?(name, "*"),
      do: not quoted and is_binary(value) and extended?(value),
      else: value == true or (is_binary(value) and (quoted or Regex.match?(@token, value)))
  end

  defp relations?(value, quoted), do: list?(value, quoted, &relation?/1)

  defp content_format?(value) do
    Regex.match?(@cardinal, value) and
      (byte_size(value) < 5 or (byte_size(value) == 5 and value <= "65535"))
  end

  defp list?(value, quoted, predicate) when is_binary(value) do
    parts = String.split(value, ~r/ +/)
    (quoted or length(parts) == 1) and Enum.all?(parts, predicate)
  end

  defp list?(_, _, _), do: false

  defp relation?(value) do
    Regex.match?(@relation, value) or
      (uri?(value) and Regex.match?(~r/\A[A-Za-z][A-Za-z0-9+.-]*:/, value))
  end

  defp language?(value),
    do:
      String.downcase(value) in @grandfathered or Regex.match?(@language, value) or
        Regex.match?(@private_language, value)

  defp extended?(value) do
    case String.split(value, "'", parts: 3) do
      [charset, language, encoded] ->
        Regex.match?(~r/\A[A-Za-z0-9!#$%&+^_`{}~-]+\z/, charset) and
          (language == "" or language?(language)) and
          Regex.match?(~r/\A(?:[A-Za-z0-9!#$&+.^_`|~-]|%[A-Fa-f0-9]{2})*\z/, encoded)

      _ ->
        false
    end
  end

  @doc false
  @spec uri?(binary()) :: boolean()
  def uri?(value) do
    valid_bytes = Regex.match?(~r/\A[A-Za-z0-9._~:\/?#\[\]@!$&'()*+,;=%-]*\z/, value)

    if valid_bytes and percent?(value) do
      parts =
        Regex.named_captures(
          ~r/\A(?:(?<scheme>[A-Za-z][A-Za-z0-9+.-]*):)?
          (?<authority>\/\/[^\/?#]*)?(?<path>[^?#]*)
          (?:\?(?<query>[^#]*))?(?:\#(?<fragment>.*))?\z/x,
          value
        )

      path?(parts["path"]) and query?(parts["query"]) and query?(parts["fragment"]) and
        relative_path?(parts) and authority?(parts["authority"])
    else
      false
    end
  end

  defp path?(value), do: Regex.match?(~r/\A[A-Za-z0-9._~:\/@!$&'()*+,;=%-]*\z/, value)
  defp query?(value), do: Regex.match?(~r/\A[A-Za-z0-9._~:\/?@!$&'()*+,;=%-]*\z/, value)

  defp relative_path?(%{"scheme" => "", "authority" => "", "path" => path}),
    do: not String.contains?(hd(String.split(path, "/", parts: 2)), ":")

  defp relative_path?(_), do: true
  defp authority?(""), do: true

  defp authority?("//" <> value) do
    parts =
      Regex.named_captures(
        ~r/\A(?:(?<userinfo>[^@]*)@)?(?<host>\[[^\]]*\]|[^:]*)(?::(?<port>[0-9]*))?\z/,
        value
      )

    not is_nil(parts) and
      Regex.match?(~r/\A[A-Za-z0-9._~:!$&'()*+,;=%-]*\z/, parts["userinfo"]) and
      host?(parts["host"])
  end

  defp host?("[" <> value) do
    literal = binary_part(value, 0, byte_size(value) - 1)

    match?({:ok, _}, :inet.parse_ipv6_address(String.to_charlist(literal))) or
      Regex.match?(~r/\A[vV][A-Fa-f0-9]+\.[A-Za-z0-9._~:!$&'()*+,;=-]+\z/, literal)
  end

  defp host?(value), do: Regex.match?(~r/\A[A-Za-z0-9._~!$&'()*+,;=%-]*\z/, value)
  defp percent?(<<>>), do: true

  defp percent?(<<"%", a, b, rest::binary>>),
    do: a in ~c"0123456789abcdefABCDEF" and b in ~c"0123456789abcdefABCDEF" and percent?(rest)

  defp percent?(<<"%", _::binary>>), do: false
  defp percent?(<<_, rest::binary>>), do: percent?(rest)
end
