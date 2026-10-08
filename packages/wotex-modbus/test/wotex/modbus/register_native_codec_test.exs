defmodule Wotex.Modbus.RegisterNativeCodecTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Modbus.{RegisterCodec, RegisterNativeCodec}
  alias Wotex.Runtime.Codec.Wire

  @moduletag :register_reference
  @configuration %{
    "registers" => 1,
    "byte_order" => "big",
    "word_order" => "big",
    "scale" => -2,
    "signed" => false
  }
  @metadata %{"format" => "packed-bcd-v1"}

  setup_all do
    parent = System.get_env("WOTEX_REGISTER_CODECS_WORKSPACE") || System.tmp_dir!()
    :absolute = Path.type(parent)
    workspace = Path.join(parent, "register-codecs-#{System.unique_integer([:positive])}")
    builds = RegisterNativeCodec.build!(workspace)
    Mix.shell().info("reference build receipts: #{Path.join(workspace, "reference-build.json")}")

    unless System.get_env("WOTEX_REGISTER_CODECS_WORKSPACE"),
      do: on_exit(fn -> File.rm_rf!(workspace) end)

    {:ok, builds: builds, programs: [builds.cpp, builds.rust]}
  end

  test "exact source, dependency, contract and executable receipts distinguish the languages",
       context do
    assert context.builds.receipt["executables"]["cpp"] !=
             context.builds.receipt["executables"]["rust"]

    assert context.builds.receipt["contract"] == RegisterCodec.contract()
    assert context.builds.receipt["configuration_schema"] == RegisterCodec.configuration_schema()

    assert context.builds.receipt["sources"]["test/native/register_codec_cpp/vendor/json.hpp"] ==
             "9bea4c8066ef4a1c206b2be5a36302f8926f7fdc6087af5d20b417d0cf103ea6"

    assert Map.has_key?(
             context.builds.receipt["sources"],
             "test/native/register_codec_rust/Cargo.lock"
           )
  end

  test "independent decoders agree on widths, all orders, sign, zero and scale extrema", context do
    for program <- context.programs,
        width <- 1..4,
        byte <- ~w(big little),
        word <- ~w(big little) do
      config =
        Map.merge(@configuration, %{
          "registers" => width,
          "byte_order" => byte,
          "word_order" => word
        })

      words =
        for <<a,
              b <- binary_part(<<0x12, 0x34, 0x56, 0x78, 0x90, 0x12, 0x34, 0x56>>, 0, width * 2)>>,
            do: if(byte == "big", do: <<a, b>>, else: <<b, a>>)

      words = if word == "big", do: words, else: Enum.reverse(words)

      with_program(program, config, fn port ->
        coefficient = Enum.at(["1234", "12345678", "123456789012", "1234567890123456"], width - 1)
        expected = decimal(coefficient, -2)
        assert_reply(port, decode(IO.iodata_to_binary(words)), result(1, expected))
        assert_reply(port, decode(IO.iodata_to_binary(words), seq: 2), result(2, expected))
      end)
    end

    for program <- context.programs,
        scale <- [-32_768, 32_767],
        {sign, coefficient} <- [{12, "123"}, {13, "-123"}] do
      config = Map.merge(@configuration, %{"signed" => true, "scale" => scale})

      with_program(program, config, fn port ->
        assert_reply(port, decode(<<0x12, 3::4, sign::4>>), result(1, decimal(coefficient, scale)))
        assert_reply(port, decode(<<0, 0x0C>>, seq: 2), result(2, decimal("0", 0)))
        assert_reply(port, decode(<<0, 0x0D>>, seq: 3), refusal(3, "unsupported_value"))
      end)
    end

    for program <- context.programs do
      with_program(program, Map.put(@configuration, "scale", 32_767), fn port ->
        assert_reply(port, decode(<<0, 0x10>>), refusal(1, "unsupported_value"))
      end)

      with_program(program, Map.put(@configuration, "scale", 32_766), fn port ->
        assert_reply(port, decode(<<0, 0x10>>), result(1, decimal("1", 32_767)))
      end)

      with_program(program, Map.put(@configuration, "registers", 4), fn port ->
        assert_reply(
          port,
          decode(:binary.copy(<<0x99>>, 8)),
          result(1, decimal("9999999999999999", -2))
        )
      end)
    end
  end

  test "every cut of a Unicode request, coalesced input and independent instances preserve canonical bytes",
       context do
    request_id = "request-🌡️-\u0000-\"-\\-\u2028"
    frame = decode(<<0x12, 0x30>>, request_id: request_id)
    bytes = encoded(frame)
    expected = result(1, decimal("123", -1)) |> Map.put("request_id", request_id)

    for program <- context.programs, cut <- 0..byte_size(bytes) do
      with_program(program, @configuration, fn port ->
        <<left::binary-size(^cut), right::binary>> = bytes
        if left != <<>>, do: RegisterNativeCodec.send_bytes(port, left)
        if right != <<>>, do: RegisterNativeCodec.send_bytes(port, right)
        assert {^expected, raw} = RegisterNativeCodec.receive_frame(port)
        assert raw == encoded(expected)
      end)
    end

    for program <- context.programs do
      port = RegisterNativeCodec.start(program)
      all = encoded(hello(@configuration)) <> encoded(decode(<<0x12, 0x34>>)) <> encoded(stop())
      RegisterNativeCodec.send_bytes(port, all)
      assert {raw, 0} = RegisterNativeCodec.collect(port)
      assert raw == encoded(ready(@configuration)) <> encoded(result(1, decimal("1234", -2)))

      ports =
        for generation <- [1, 2] do
          port = RegisterNativeCodec.start(program)
          frame = Map.put(hello(@configuration), "generation", generation)
          RegisterNativeCodec.send_bytes(port, encoded(frame))
          assert {reply, raw} = RegisterNativeCodec.receive_frame(port)
          assert reply == Map.put(ready(@configuration), "generation", generation)
          assert raw == encoded(reply)
          port
        end

      Enum.each(ports, fn port ->
        RegisterNativeCodec.send_bytes(port, encoded(stop()))
        assert 0 == RegisterNativeCodec.exit_status(port)
      end)
    end
  end

  test "malformed protocol, Unicode, duplicate keys and substituted configuration never expose diagnostics",
       context do
    hello = encoded(hello(@configuration))

    mutants =
      [
        "\n",
        "\xef\xbb\xbf" <> hello,
        String.replace(hello, "\n", "\r\n"),
        String.replace(hello, "\"v\":1", "\"v\":1,\"v\":1"),
        String.replace(hello, "\"scale\":-2", "\"scale\":-2,\"scale\":-2"),
        String.replace(hello, "\"v\":1", "\"v\":1.0"),
        String.replace(hello, "\"v\":1", "\"v\":1e0"),
        String.replace(hello, "\"v\":1", "\"v\":2"),
        String.replace(hello, "\"generation\":1", "\"generation\":9007199254740992"),
        String.replace(hello, "\"generation\":1", "\"generation\":1111111111111111111"),
        String.replace(hello, "register-reference", "\\ud800"),
        String.replace(hello, "register-reference", <<255>>),
        Jason.encode!(
          Map.put(hello(@configuration), "configuration_sha256", String.duplicate("f", 64))
        ) <> "\n",
        encoded(Map.put(hello(@configuration), "contract_sha256", String.duplicate("f", 64))),
        Jason.encode!(Map.put(hello(@configuration), "extra", "configuration-secret-canary")) <>
          "\n",
        Jason.encode!(
          Map.put(hello(@configuration), "configuration", Map.put(@configuration, "registers", 5))
        ) <> "\n",
        "{\"secret\":\"output-secret-canary\"}\n",
        encoded(decode(<<0x12, 0x34>>))
      ]

    for program <- context.programs, bytes <- mutants do
      port = RegisterNativeCodec.start(program)
      RegisterNativeCodec.send_bytes(port, bytes)
      assert {<<>>, 65} = RegisterNativeCodec.collect(port)
    end
  end

  test "request fields, Base64 pad bits and sequence direction faults close without reply",
       context do
    decode = decode(<<0x12, 0x34>>)

    mutants = [
      Map.put(decode, "seq", 0),
      Map.put(decode, "seq", 2),
      Map.put(decode, "seq", 9_007_199_254_740_992),
      Map.put(decode, "request_id", ""),
      Map.put(decode, "request_id", String.duplicate("x", 257)),
      Map.put(decode, "budget_ms", 0),
      Map.put(decode, "budget_ms", 1001),
      Map.put(decode, "extra", "input-secret-canary"),
      Map.put(decode, "metadata", []),
      Map.put(decode, "metadata", %{"x" => %{"nested" => "input-secret-canary"}}),
      Map.put(decode, "metadata", Map.new(1..17, &{Integer.to_string(&1), true})),
      Map.put(decode, "metadata", %{"x" => String.duplicate("x", 257)}),
      Map.put(decode, "bytes", %{"type" => "bytes", "base64" => "AR=="}),
      Map.put(decode, "bytes", %{"type" => "bytes", "base64" => "AQJ="}),
      Map.put(decode, "bytes", %{"type" => "bytes", "base64" => "===="}),
      Map.put(decode, "bytes", %{"type" => "bytes", "base64" => "AQ"}),
      Map.put(decode, "bytes", %{"type" => "bytes", "base64" => "A Q="}),
      Map.put(decode, "bytes", %{
        "type" => "bytes",
        "base64" => Base.encode64(:binary.copy(<<0>>, 65_537))
      })
    ]

    for program <- context.programs, mutant <- mutants do
      port = started(program, @configuration)
      RegisterNativeCodec.send_bytes(port, Jason.encode!(mutant) <> "\n")
      assert {<<>>, 65} = RegisterNativeCodec.collect(port)
    end

    for program <- context.programs do
      port = started(program, @configuration)
      RegisterNativeCodec.send_bytes(port, encoded(hello(@configuration)))
      assert {<<>>, 65} = RegisterNativeCodec.collect(port)
    end
  end

  test "frame and input equality bounds accept while one-over values refuse", context do
    hello = encoded(hello(@configuration))

    for program <- context.programs do
      port = RegisterNativeCodec.start(program)

      RegisterNativeCodec.send_bytes(
        port,
        String.duplicate(" ", 131_072 - byte_size(hello)) <> hello
      )

      assert {frame, _} = RegisterNativeCodec.receive_frame(port)
      assert frame == ready(@configuration)
      assert_reply(port, decode(:binary.copy(<<0>>, 65_536)), refusal(1, "invalid_input"))
      RegisterNativeCodec.send_bytes(port, encoded(stop()))
      assert 0 == RegisterNativeCodec.exit_status(port)
      port = RegisterNativeCodec.start(program)

      RegisterNativeCodec.send_bytes(
        port,
        String.duplicate(" ", 131_073 - byte_size(hello)) <> hello
      )

      assert {<<>>, 65} = RegisterNativeCodec.collect(port)

      with_program(program, @configuration, fn port ->
        assert_reply(port, decode(<<>>), refusal(1, "invalid_input"))
        assert_reply(port, decode(<<0xAB, 0xCD>>, seq: 2), refusal(2, "invalid_input"))

        assert_reply(
          port,
          decode(<<0x12, 0x34>>, seq: 3, metadata: %{"format" => "other"}),
          refusal(3, "unsupported_format")
        )
      end)
    end
  end

  defp started(program, config) do
    port = RegisterNativeCodec.start(program)
    assert_reply(port, hello(config), ready(config))
    port
  end

  defp with_program(program, config, callback) do
    port = started(program, config)

    try do
      callback.(port)
      RegisterNativeCodec.send_bytes(port, encoded(stop()))
      assert 0 == RegisterNativeCodec.exit_status(port)
    after
      RegisterNativeCodec.close(port)
    end
  end

  defp assert_reply(port, frame, expected) do
    RegisterNativeCodec.send_bytes(port, encoded(frame))
    assert {^expected, raw} = RegisterNativeCodec.receive_frame(port)
    assert raw == encoded(expected)
  end

  defp hello(config) do
    %{
      "v" => 1,
      "type" => "hello",
      "instance_id" => "register-reference",
      "generation" => 1,
      "descriptor_sha256" => String.duplicate("a", 64),
      "contract_id" => RegisterCodec.contract()["id"],
      "contract_sha256" => RegisterCodec.contract()["sha256"],
      "configuration_sha256" =>
        :crypto.hash(:sha256, canonical(config)) |> Base.encode16(case: :lower),
      "configuration" => config,
      "decode_ms" => 1000
    }
  end

  defp ready(config) do
    hello(config)
    |> Map.delete("configuration")
    |> Map.put("type", "ready")
  end

  defp decode(bytes, opts \\ []),
    do: %{
      "v" => 1,
      "type" => "decode",
      "seq" => Keyword.get(opts, :seq, 1),
      "request_id" => Keyword.get(opts, :request_id, "request"),
      "budget_ms" => 1000,
      "bytes" => %{"type" => "bytes", "base64" => Base.encode64(bytes)},
      "metadata" => Keyword.get(opts, :metadata, @metadata)
    }

  defp result(seq, value),
    do: %{"v" => 1, "type" => "result", "seq" => seq, "request_id" => "request", "value" => value}

  defp refusal(seq, code),
    do: %{"v" => 1, "type" => "refusal", "seq" => seq, "request_id" => "request", "code" => code}

  defp decimal(coefficient, exponent),
    do: %{"type" => "decimal", "coefficient" => coefficient, "exponent" => exponent}

  defp stop, do: %{"v" => 1, "type" => "stop"}

  defp encoded(frame) do
    {:ok, bytes} = Wire.encode(frame)
    bytes
  end

  defp canonical(config),
    do:
      "{" <>
        Enum.map_join(Enum.sort(config), ",", fn {key, value} ->
          Jason.encode!(key) <> ":" <> Jason.encode!(value)
        end) <> "}"
end
