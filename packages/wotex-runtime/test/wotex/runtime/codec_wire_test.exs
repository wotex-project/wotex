defmodule Wotex.Runtime.CodecWireTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Runtime.Codec.{Value, Wire}
  alias Wotex.Runtime.Implementation.Error

  @vectors __DIR__
           |> Path.join("../../support/codec_wire_vectors.json")
           |> File.read!()
           |> Jason.decode!()
           |> Map.fetch!("vectors")
  @safe 9_007_199_254_740_991
  @stop %{"v" => 1, "type" => "stop"}

  test "authored vectors cover every frame and exact canonical bytes" do
    for %{"frame" => frame, "canonical" => bytes} <- @vectors do
      assert {:ok, ^frame} = Wire.validate(frame)
      assert {:ok, ^bytes} = Wire.encode(frame)
      assert {:ok, ^frame} = Wire.decode(bytes)
      assert {:ok, ^frame} = Wire.decode(" \t" <> bytes)
    end

    # Escaped controls are valid string content; literal framing controls are not.
    frame =
      Map.put(vector("result"), "value", %{"type" => "text", "value" => "\r\n\u0000é\u{10000}"})

    assert {:ok, bytes} = Wire.encode(frame)
    assert {:ok, ^frame} = Wire.decode(bytes)
    assert bytes =~ "\\r\\n\\u0000é\u{10000}"
  end

  test "fragmentation at every byte including UTF-8 and coalesced frames preserves order" do
    frame = Map.put(vector("result"), "value", %{"type" => "text", "value" => "é\u{10000}"})
    {:ok, bytes} = Wire.encode(frame)

    for index <- 0..(byte_size(bytes) - 1) do
      <<first::binary-size(^index), rest::binary>> = bytes
      assert {:ok, [], partial} = Wire.feed(stream(), first)
      assert {:ok, [^frame], complete} = Wire.feed(partial, rest)
      assert complete.buffer == <<>>
    end

    joined = Enum.map_join(@vectors, & &1["canonical"])
    assert {:ok, frames, partial} = Wire.feed(stream(), joined <> "{\"v\":")
    assert frames == Enum.map(@vectors, & &1["frame"])
    assert partial.buffer == "{\"v\":"
    assert {:ok, [@stop], complete} = Wire.feed(partial, "1,\"type\":\"stop\"}\n")
    assert complete.buffer == <<>>
    assert Wire.feed(complete, <<>>) == {:ok, [], complete}
  end

  test "malformed lexical tokens, duplicates and framing errors have fixed redacted errors" do
    bad = [
      nil,
      <<>>,
      "\n",
      " \n",
      "{}\n",
      "[]\n",
      "{\"v\":1,\"type\":\"stop\"}",
      "{\"v\":1,\"type\":\"stop\"}\r\n",
      <<0xEF, 0xBB, 0xBF>> <> "{\"v\":1,\"type\":\"stop\"}\n",
      "{\"v\":1,\"v\":1,\"type\":\"stop\"}\n",
      "{\"v\":1.0,\"type\":\"stop\"}\n",
      "{\"v\":1e0,\"type\":\"stop\"}\n",
      "{\"v\":01,\"type\":\"stop\"}\n",
      "{\"v\":1,\"type\":\"stop\",}\n",
      "{\"v\":1,\"type\":\"stop\"}canary\n",
      "{\"v\":1,\"type\":\"stop\"}\n{\"v\":1,\"type\":\"stop\"}\n",
      "{\"v\":1,\"type\":\"stop\"\r}\n",
      "{\"v\":1,\"type\":\"stop\"\n}\n",
      "{\"v\":1,\"type\":\"\\ud800\"}\n",
      "{\"v\":1,\"type\":\"\\udc00\"}\n",
      "{\"v\":1,\"type\":\"\\ud800\\u0041\"}\n",
      ~s({"v":1,"type":"canary) <> <<255>> <> "\"}\n",
      "{\"v\":1,\"type\":\"stop\u0000\"}\n"
    ]

    for bytes <- bad, do: assert_fault(Wire.decode(bytes))
    decode = vector("decode")
    raw = Jason.encode!(decode)

    assert_fault(
      Wire.decode(
        String.replace(raw, ~s("format":"uint8"), ~s("format":"uint8","format":"uint8")) <>
          "\n"
      )
    )

    assert_fault(Wire.decode(String.replace(raw, "\"seq\":1", "\"seq\":9007199254740992") <> "\n"))

    assert_fault(
      Wire.decode(
        String.replace(
          raw,
          ~s("metadata":{"format":"uint8"}),
          ~s("metadata":{"k":) <>
            String.duplicate("[", 25) <> "0" <> String.duplicate("]", 25) <> "}"
        ) <> "\n"
      )
    )
  end

  test "closed frame grammar refuses altered fields, identities and configuration hashes" do
    for frame <- Enum.map(@vectors, & &1["frame"]) do
      for key <- Map.keys(frame), do: assert_fault(Wire.validate(Map.delete(frame, key)))
      assert_fault(Wire.encode(Map.put(frame, "canary", "secret-canary")))
      for version <- [0, 1.0, 2, "1"], do: assert_fault(Wire.validate(Map.put(frame, "v", version)))
    end

    for bad <- [nil, 1, %{}, %{:v => 1, :type => "stop"}, Map.put(@stop, "type", "foreign")],
        do: assert_fault(Wire.validate(bad))

    hello = vector("hello")

    for {field, values} <- [
          {"instance_id", ["", "with space", String.duplicate("i", 129)]},
          {"generation", [0, -1, @safe + 1, 1.0]},
          {"descriptor_sha256", ["", String.duplicate("D", 64), String.duplicate("d", 63)]},
          {"contract_id", ["", "foreign contract"]},
          {"contract_sha256", [nil, String.duplicate("C", 64)]},
          {"decode_ms", [0, 1001, 1.0]},
          {"configuration_sha256", [nil, String.duplicate("0", 64)]},
          {"configuration", [nil, %{"k" => []}, %{"k" => "configuration-canary"}]}
        ],
        bad <- values,
        do: assert_fault(Wire.validate(Map.put(hello, field, bad)))

    for type <- ["result", "refusal", "decode"], field <- ["seq", "request_id"] do
      values =
        if field == "seq",
          do: [0, -1, @safe + 1, 1.0, "1"],
          else: ["", <<255>>, String.duplicate("é", 129), nil]

      for bad <- values, do: assert_fault(Wire.validate(Map.put(vector(type), field, bad)))
    end

    for code <- ["foreign", :invalid_input, nil],
        do: assert_fault(Wire.validate(Map.put(vector("refusal"), "code", code)))

    for code <- ~w(invalid_input unsupported_format unsupported_value output_limit),
        do: assert({:ok, _} = Wire.validate(Map.put(vector("refusal"), "code", code)))

    for field <- ["generation", "decode_ms"] do
      maximum = if field == "generation", do: @safe, else: 1000
      for value <- [1, maximum], do: assert({:ok, _} = Wire.validate(Map.put(hello, field, value)))
    end
  end

  test "decode input expansion and metadata/counter limits admit equality and refuse one over" do
    frame = vector("decode")

    for size <- [0, 65_536] do
      bytes = %{"type" => "bytes", "base64" => Base.encode64(:binary.copy(<<0>>, size))}
      exact = Map.put(frame, "bytes", bytes)
      assert {:ok, encoded} = Wire.encode(exact)
      assert {:ok, ^exact} = Wire.decode(encoded)
    end

    for size <- [65_537, 65_538, 65_539] do
      bytes = %{"type" => "bytes", "base64" => Base.encode64(:binary.copy(<<0>>, size))}
      assert_fault(Wire.validate(Map.put(frame, "bytes", bytes)))
    end

    for base64 <- ["AR==", "AQ", "AQ=", "AQ===", " A Q==", "AQ==\n", "_w==", "A===", 1] do
      assert_fault(Wire.validate(Map.put(frame, "bytes", %{"type" => "bytes", "base64" => base64})))
    end

    for bytes <- [
          nil,
          %{"base64" => "AQ=="},
          %{"type" => "text", "value" => "a"},
          %{"type" => "bytes", "base64" => "AQ==", "extra" => nil}
        ],
        do: assert_fault(Wire.validate(Map.put(frame, "bytes", bytes)))

    exact =
      frame
      |> Map.put("seq", @safe)
      |> Map.put("request_id", String.duplicate("é", 128))
      |> Map.put("budget_ms", 1)

    assert {:ok, _} = Wire.validate(exact)

    for budget <- [0, 1001, nil, 1.0],
        do: assert_fault(Wire.validate(Map.put(frame, "budget_ms", budget)))

    for metadata <- [
          nil,
          %{"k" => []},
          %{"k" => 1.0},
          Map.new(1..17, &{Integer.to_string(&1), nil})
        ],
        do: assert_fault(Wire.validate(Map.put(frame, "metadata", metadata)))

    assert {:ok, _} =
             Wire.validate(
               Map.put(frame, "metadata", Map.new(1..16, &{Integer.to_string(&1), nil}))
             )
  end

  test "frame and retained queue bounds include LF, reject forged state and hide bytes" do
    {:ok, encoded} = Wire.encode(@stop)
    padding = 131_072 - byte_size(encoded)
    exact = String.duplicate(" ", padding) <> encoded
    assert byte_size(exact) == 131_072
    assert {:ok, @stop} = Wire.decode(exact)
    assert_fault(Wire.decode(" " <> exact))
    assert {:ok, [@stop, @stop], _} = Wire.feed(stream(), exact <> exact)
    assert_fault(Wire.feed(stream(), exact <> exact <> " "))
    partial = binary_part(exact, 0, 131_071)
    assert {:ok, [], state} = Wire.feed(stream(), partial)
    assert {:ok, [@stop], _} = Wire.feed(state, "\n")
    assert_fault(Wire.feed(state, " "))

    small = stream(%{frame_bytes: byte_size(encoded), queue_bytes: byte_size(encoded)})
    assert {:ok, [@stop], _} = Wire.feed(small, encoded)

    assert_fault(
      Wire.feed(stream(%{frame_bytes: byte_size(encoded) - 1, queue_bytes: 262_144}), encoded)
    )

    short_queue = stream(%{frame_bytes: 131_072, queue_bytes: byte_size(encoded) - 1})
    assert_fault(Wire.feed(short_queue, encoded))

    for bad <- [
          nil,
          %{},
          %{__struct__: Wire},
          Map.put(stream(), :extra, "canary"),
          %{stream() | buffer: "\n"},
          %{stream() | buffer: 1},
          %{stream() | frame_bytes: 0},
          %{small | buffer: String.duplicate("x", byte_size(encoded))}
        ],
        do: assert_fault(Wire.feed(bad, <<>>))

    assert_fault(Wire.feed(stream(), :bad))
    assert_fault(Wire.feed(%{stream(%{frame_bytes: 100, queue_bytes: 1}) | buffer: "xx"}, <<>>))

    for bad <- [
          nil,
          %{},
          %{frame_bytes: 1, queue_bytes: 1, extra: 1},
          %{frame_bytes: 0, queue_bytes: 1},
          %{frame_bytes: 131_073, queue_bytes: 1},
          %{frame_bytes: 1, queue_bytes: 262_145},
          %{frame_bytes: 1.0, queue_bytes: 1}
        ] do
      assert {:error, %Error{code: :invalid_configuration, phase: :admission}} = Wire.new(bad)
    end

    limits = [%{frame_bytes: 1, queue_bytes: 1}, %{frame_bytes: 131_072, queue_bytes: 262_144}]

    for limits <- limits,
        do: assert({:ok, _} = Wire.new(limits))

    assert {:ok, [], sensitive} = Wire.feed(stream(), "configuration-canary")
    refute inspect(sensitive) =~ "configuration-canary"
    assert_fault(Wire.feed(stream(), encoded <> "\n"))
  end

  test "full wire nodes/depth and output value limits are revalidated before encoding" do
    groups =
      Enum.map([256, 256, 256, 251], fn count ->
        %{
          "type" => "object",
          "entries" =>
            Enum.map(1..count, fn i ->
              %{
                "key" => String.pad_leading(Integer.to_string(i), 3, "0"),
                "value" => %{"type" => "null"}
              }
            end)
        }
      end)

    value = %{"type" => "list", "items" => groups}
    exact = Map.put(vector("result"), "value", value)
    assert {:ok, encoded} = Wire.encode(exact)
    assert {:ok, ^exact} = Wire.decode(encoded)

    [first | rest] = groups
    [entry | entries] = first["entries"]

    first =
      Map.put(first, "entries", [
        Map.put(entry, "value", %{"type" => "boolean", "value" => true}) | entries
      ])

    over = %{"type" => "list", "items" => [first | rest]}
    assert {:ok, _} = Value.validate(over)
    assert_fault(Wire.validate(Map.put(exact, "value", over)))

    nested =
      Enum.reduce(1..7, %{"type" => "object", "entries" => []}, fn _, child ->
        %{"type" => "object", "entries" => [%{"key" => "a", "value" => child}]}
      end)

    depth = Map.put(vector("result"), "value", nested)
    assert {:ok, bytes} = Wire.encode(depth)
    assert {:ok, ^depth} = Wire.decode(bytes)

    for value <- [
          nil,
          %{"type" => "uint", "value" => "18446744073709551616"},
          %{"type" => "text", "value" => String.duplicate("x", 4097)}
        ],
        do: assert_fault(Wire.validate(Map.put(vector("result"), "value", value)))
  end

  defp stream(limits \\ %{frame_bytes: 131_072, queue_bytes: 262_144}) do
    {:ok, wire} = Wire.new(limits)
    wire
  end

  defp vector(type), do: Enum.find(@vectors, &(&1["id"] == type))["frame"]

  defp assert_fault(result) do
    assert {:error, %Error{code: :protocol_fault, phase: :decode} = error} = result
    assert error == Error.new(:protocol_fault, :decode, %{})
    refute inspect(error) =~ "canary"
  end
end
