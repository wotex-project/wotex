defmodule Wotex.CoAP.LinkFormatTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.CoAP.{Error, LinkFormat}

  test "WCO-S04 WCO-D03 WCO-V11 grammar preserves strings, target context and attribute order" do
    for {attribute, expected} <- [
          {"RT=\"temperature-c https://example.test/rt\"",
           {"RT", "temperature-c https://example.test/rt"}},
          {"if=urn:example:sensor", {"if", "urn:example:sensor"}},
          {"sz=" <> String.duplicate("9", 100), {"sz", String.duplicate("9", 100)}},
          {"ct=\"0 40 50\"", {"ct", "0 40 50"}},
          {"ct=0", {"ct", "0"}},
          {"obs", {"obs", true}},
          {"unknown", {"unknown", true}},
          {"rev=alternate", {"rev", "alternate"}},
          {"media=\"screen, print\"", {"media", "screen, print"}},
          {"type=\"application/link-format\"", {"type", "application/link-format"}},
          {"title=\"smörgås \\\"east\\\" \\\\ path\"", {"title", "smörgås \"east\" \\ path"}},
          {"anchor=\"../x?key=a,b#here\"", {"anchor", "../x?key=a,b#here"}},
          {"title*=UTF-8'sv'en%20titel", {"title*", "UTF-8'sv'en%20titel"}},
          {"x*=ISO-8859-1''%E9", {"x*", "ISO-8859-1''%E9"}}
        ] do
      assert {:ok, [%{href: "https://example.test/a,b", attributes: [^expected]}]} =
               LinkFormat.decode("<https://example.test/a,b>;" <> attribute)
    end

    for language <-
          ~w(en en-US sv-SE zh-Hant-TW de-CH-1901 sl-rozaj en-a-extend1-x-private x-test i-klingon) do
      assert {:ok, [%{attributes: [{"hreflang", ^language}]}]} =
               LinkFormat.decode("</>;hreflang=" <> language)
    end

    for href <- [
          "",
          "../x",
          "/x%20y",
          "?a=b,c",
          "#fragment",
          "urn:example:thing",
          "coap://[::1]:5683/x",
          "//example.test/x",
          "http://[v1.a:b]/x",
          "http://host:999999999999999999999/x",
          "http://user:password@host:/x",
          "//"
        ] do
      assert {:ok, [%{href: ^href}]} = LinkFormat.decode("<" <> href <> ">")
    end
  end

  test "WCO-D03 WCO-V11 malformed standard attributes are not generic extension values" do
    for attribute <-
          [
            "title=unquoted",
            "title*=\"UTF-8''a\"",
            "title*=UTF-8",
            "title*=UTF-8'en'%zz",
            "title*=UTF-8'123'a",
            "title*=UTF-8''a'b",
            "x*=plain",
            "x*",
            "anchor=/x",
            "anchor",
            "anchor=\"/bad path\"",
            "type=true",
            "type=\"a/b;c=d\"",
            "sz=00",
            "sz=+1",
            "sz=-1",
            "sz=\"1\"",
            "sz",
            "ct=65536",
            "ct=999999999999999999999999",
            "ct=00",
            "ct=\"1  02\"",
            "ct=\"\"",
            "ct",
            "media=\"\"",
            "media",
            "hreflang=\"en\"",
            "hreflang=e",
            "hreflang=en_uk",
            "hreflang=en-",
            "hreflang",
            "rt=Uppercase",
            "rt=\" leading\"",
            "rt=\"trailing \"",
            "rt",
            "if=\"\"",
            "rel",
            "rel=\"relative/path\"",
            "x=",
            "x=hello world",
            "x=y\"",
            "x**=v",
            "=v"
          ] do
      assert {:error, %Error{code: :invalid_link_format}} = LinkFormat.decode("</>;" <> attribute),
             attribute
    end

    for body <- [
          nil,
          %{},
          <<255>>,
          " ",
          "</>,",
          "</> ,</x>",
          "</>;",
          "<",
          "<x",
          "</x>garbage",
          "</>;title=\"x\\",
          "</>;title=\"x\\\"",
          "</>;title=\"x\"tail",
          "</x y>",
          "</x%>",
          "</x%gg>",
          "<1invalid:thing>",
          "</a[b]>",
          "<http://[::no]/x>",
          "<http://[bad]/x>",
          "<http://[::1]junk/x>",
          "<http://user@@host/x>",
          "<http://host:abc/x>",
          "</>;\nobs",
          "</>;title=\"\t\"",
          "</>;title=\"" <> <<127>> <> "\""
        ] do
      assert {:error, %Error{code: :invalid_link_format}} = LinkFormat.decode(body), inspect(body)
    end
  end

  test "WCO-D03 WCO-V11 multiplicity uses explicit singleton and first-occurrence rules" do
    for key <- ~w(rt if sz anchor media type) do
      value =
        case key do
          "sz" -> "1"
          "anchor" -> "\"/x\""
          "type" -> "a/b"
          _ -> "a"
        end

      assert {:error, %Error{code: :invalid_link_format}} =
               LinkFormat.decode(
                 "</>;" <> key <> "=" <> value <> ";" <> String.upcase(key) <> "=" <> value
               )
    end

    assert {:ok,
            [
              %{
                attributes: [
                  {"title", "first"},
                  {"title*", "UTF-8''one"},
                  {"rel", "a"},
                  {"x", "1"},
                  {"x", "2"}
                ]
              }
            ]} =
             LinkFormat.decode(
               ~s|</>;title="first";TITLE="second";title*=UTF-8''one;title*=UTF-8''two;rel=a;rel=b;x=1;x=2|
             )

    assert {:ok, [%{attributes: [{"obs", true}, {"ct", "65535"}]}]} =
             LinkFormat.decode("</>;obs=1;obs=\"ignored\";ct=65535")

    assert {:ok, [%{attributes: [{"obs", true}]}]} = LinkFormat.decode("</>;obs=\"\"")
    assert {:error, %Error{code: :invalid_link_format}} = LinkFormat.decode("</>;HREF=x")

    assert {:error, %Error{code: :invalid_link_format}} =
             LinkFormat.decode("</>;title=\"first\";title=bad")
  end

  test "WCO-C02 WCO-D03 WCO-V11 limits fail during scanning including discarded attributes" do
    for options <- [
          nil,
          [:bad],
          [max_links: 0],
          [max_links: 257],
          [max_attributes: 33],
          [max_body_bytes: 65_537],
          [max_token_bytes: 1025],
          [max_links: 1, max_links: 2],
          [{:max_links, 1} | nil],
          [max_links: true],
          [unknown: 1]
        ] do
      assert {:error, %Error{code: :invalid_link_options}} = LinkFormat.decode("", options)
    end

    for {body, options, field, maximum} <- [
          {"</>", [max_body_bytes: 2], :body, 2},
          {"</a>,</b>", [max_links: 1], :links, 1},
          {"</>;x;y", [max_attributes: 1], :attributes, 1},
          {~s|</>;title="a";title="b"|, [max_attributes: 1], :attributes, 1},
          {"</abc>", [max_token_bytes: 3], :token, 3},
          {"</>;abc=1", [max_token_bytes: 2], :token, 2},
          {"</>;x=abc", [max_token_bytes: 2], :token, 2},
          {"</>;x=\"abc\"", [max_token_bytes: 2], :token, 2},
          {"</>;x=\"a\\\"\"", [max_token_bytes: 2], :token, 2}
        ] do
      assert {:error, %Error{code: :link_limit, field: ^field, details: %{limit: ^maximum}}} =
               LinkFormat.decode(body, options)
    end

    for body <- ["</>", "</abc>", "</>;x=\"abc\"", "</>;x=\"a\\\"\""] do
      assert {:ok, _} = LinkFormat.decode(body, max_token_bytes: 4, max_body_bytes: byte_size(body))
    end

    assert {:ok, links} =
             LinkFormat.decode(Enum.join(List.duplicate("</>;x;y", 256), ","), max_attributes: 2)

    assert length(links) == 256
  end

  test "WCO-D03 WCO-V11 hard maxima accept exact-size descriptions and reject one extra byte" do
    segment = "</>;x=" <> String.duplicate("a", 1024)
    prefix = Enum.join(List.duplicate(segment, 63), ",") <> ",</>;x="
    body = prefix <> String.duplicate("b", 65_536 - byte_size(prefix))
    assert byte_size(body) == 65_536
    assert {:ok, links} = LinkFormat.decode(body)
    assert length(links) == 64

    assert {:error, %Error{code: :link_limit, field: :body, details: %{limit: 65_536}}} =
             LinkFormat.decode(body <> "b")

    body = "</>" <> String.duplicate(";x", 32)
    assert {:ok, [%{attributes: attributes}]} = LinkFormat.decode(body)
    assert length(attributes) == 32
    assert {:error, %Error{field: :attributes}} = LinkFormat.decode(body <> ";x")
    assert {:error, %Error{field: :token}} = LinkFormat.decode(segment <> "a")
  end

  property "WCO-D03 WCO-V11 quoted delimiters and escapes round-trip without creating links" do
    check all(bytes <- list_of(integer(32..126), max_length: 128)) do
      value = List.to_string(bytes)

      encoded =
        value
        |> String.replace("\\", "\\\\")
        |> String.replace("\"", "\\\"")

      assert {:ok, [%{href: "/x", attributes: [{"title", ^value}, {"obs", true}]}]} =
               LinkFormat.decode("</x>;title=\"" <> encoded <> "\";obs")
    end
  end

  property "WCO-C02 WCO-D03 arbitrary binary descriptions always produce a bounded result" do
    check all(body <- binary(max_length: 1024)) do
      case LinkFormat.decode(body, max_links: 4, max_attributes: 4, max_token_bytes: 16) do
        {:ok, links} ->
          assert length(links) <= 4
          assert Enum.all?(links, &(length(&1.attributes) <= 4 and byte_size(&1.href) <= 16))

        {:error, %Error{code: code}} ->
          assert code in [:invalid_link_format, :link_limit]
      end
    end
  end
end
