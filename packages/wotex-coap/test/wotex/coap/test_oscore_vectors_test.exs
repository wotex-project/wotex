Code.require_file("../../support/oscore.ex", __DIR__)

defmodule Wotex.CoAP.TestOSCOREVectorsTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.CoAP.Test.OSCORE

  # RFC 8613 (July 2019) Appendix C test vectors for the test-owned OSCORE peer.

  @secret Base.decode16!("0102030405060708090A0B0C0D0E0F10")

  test "RFC 8613 C.1.1 derives client keys, Common IV and nonces with a Master Salt" do
    context = OSCORE.context(@secret, hex("9e7ca92223786340"), <<>>, <<1>>)

    assert OSCORE.info(<<>>, "Key", 16) == hex("8540f60a634b657910")
    assert OSCORE.info(<<1>>, "Key", 16) == hex("854101f60a634b657910")
    assert OSCORE.info(<<>>, "IV", 13) == hex("8540f60a6249560d")
    assert context.sender_key == hex("f0910ed7295e6ad4b54fc793154302ff")
    assert context.recipient_key == hex("ffb14e093c94c9cac9471648b4f98710")
    assert context.common_iv == hex("4622d4dd6d944168eefb54987c")
    assert OSCORE.nonce(context, <<>>, <<0>>) == hex("4622d4dd6d944168eefb54987c")
    assert OSCORE.nonce(context, <<1>>, <<0>>) == hex("4722d4dd6d944169eefb54987c")
  end

  test "RFC 8613 C.2.1 derives client keys, Common IV and nonces without a Master Salt" do
    context = OSCORE.context(@secret, <<>>, <<0>>, <<1>>)

    assert context.sender_key == hex("321b26943253c7ffb6003b0b64d74041")
    assert context.recipient_key == hex("e57b5635815177cd679ab4bcec9d7dda")
    assert context.common_iv == hex("be35ae297d2dace910c52e99f9")
    assert OSCORE.nonce(context, <<0>>, <<0>>) == hex("bf35ae297d2dace910c52e99f9")
    assert OSCORE.nonce(context, <<1>>, <<0>>) == hex("bf35ae297d2dace810c52e99f9")
  end

  test "RFC 8613 C.4 and C.5 protect a request" do
    salted = OSCORE.context(@secret, hex("9e7ca92223786340"), <<>>, <<1>>)
    plaintext = OSCORE.plaintext(1, [{11, "tv1"}], <<>>)
    piv = OSCORE.piv(20)

    assert plaintext == hex("01b3747631")
    assert piv == <<0x14>>
    assert OSCORE.aad(<<>>, piv) == hex("8368456e63727970743040488501810a40411440")
    assert OSCORE.nonce(salted, <<>>, piv) == hex("4622d4dd6d944168eefb549868")
    assert OSCORE.option(piv, <<>>) == hex("0914")

    assert OSCORE.seal(
             salted.sender_key,
             OSCORE.nonce(salted, <<>>, piv),
             OSCORE.aad(<<>>, piv),
             plaintext
           ) ==
             hex("612f1092f1776f1c1668b3825e")

    unsalted = OSCORE.context(@secret, <<>>, <<0>>, <<1>>)
    assert OSCORE.aad(<<0>>, piv) == hex("8368456e63727970743040498501810a4100411440")
    assert OSCORE.nonce(unsalted, <<0>>, piv) == hex("bf35ae297d2dace910c52e99ed")
    assert OSCORE.option(piv, <<0>>) == hex("091400")

    assert OSCORE.seal(
             unsalted.sender_key,
             OSCORE.nonce(unsalted, <<0>>, piv),
             OSCORE.aad(<<0>>, piv),
             plaintext
           ) ==
             hex("4ed339a5a379b0b8bc731fffb0")
  end

  test "RFC 8613 C.7 and C.8 protect responses without and with a Partial IV" do
    server = OSCORE.context(@secret, hex("9e7ca92223786340"), <<1>>, <<>>)
    request_piv = OSCORE.piv(20)
    aad = OSCORE.aad(<<>>, request_piv)
    plaintext = OSCORE.plaintext(69, [], "Hello World!")
    assert plaintext == hex("45ff48656c6c6f20576f726c6421")

    request_nonce = OSCORE.nonce(server, <<>>, request_piv)
    assert OSCORE.option(nil, nil) == <<>>

    assert OSCORE.seal(server.sender_key, request_nonce, aad, plaintext) ==
             hex("dbaad1e9a7e7b2a813d3c31524378303cdafae119106")

    response_nonce = OSCORE.nonce(server, <<1>>, OSCORE.piv(0))
    assert response_nonce == hex("4722d4dd6d944169eefb54987c")
    assert OSCORE.option(OSCORE.piv(0), nil) == hex("0100")
    sealed = OSCORE.seal(server.sender_key, response_nonce, aad, plaintext)
    assert sealed == hex("4d4c13669384b67354b2b6175ff4b8658c666a6cf88e")

    client = OSCORE.context(@secret, hex("9e7ca92223786340"), <<>>, <<1>>)
    assert {:ok, ^plaintext} = OSCORE.open(client.recipient_key, response_nonce, aad, sealed)
    assert :error = OSCORE.open(client.recipient_key, request_nonce, aad, sealed)
    assert {:ok, %{piv: <<0>>, kid: nil}} = OSCORE.parse_option(hex("0100"))
    assert {:ok, %{piv: <<0x14>>, kid: <<0>>}} = OSCORE.parse_option(hex("091400"))
    assert {:ok, message} = OSCORE.parse_plaintext(plaintext)
    assert {message.code, message.payload} == {69, "Hello World!"}
  end

  defp hex(value), do: Base.decode16!(value, case: :lower)
end
