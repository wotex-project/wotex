Code.require_file("../../support/bridge_wire_fixture.ex", __DIR__)

defmodule Wotex.Matter.BridgeWireTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.Matter.Bridge.Wire
  alias Wotex.Matter.{BridgeWireFixture, Error}

  defp decode(frame),
    do: Wire.decode_request(BridgeWireFixture.encode(frame), BridgeWireFixture.generation())

  defp refused(frame) do
    assert {:error, %Error{code: :invalid_frame, class: :protocol, effect: :none, details: %{}}} =
             decode(frame)
  end

  test "request decoding preserves complete inert metadata and exact identity widths" do
    frame = BridgeWireFixture.frame()
    assert {:ok, request} = decode(frame)
    assert request.id == 0xFFFFFFFFFFFFFFFF
    assert request.deadline_native_ms == request.id
    assert request.thing == <<0, 255>>
    assert request.generation == BridgeWireFixture.generation()
    assert request.operation == :read and request.payload == nil

    assert request.principal == %{
             fabric_index: 254,
             auth_mode: :case,
             subject: 0xFFFFFFFFFFFFFFFF,
             cats: [1, 0, 0xFFFFFFFF],
             is_commissioning: true
           }

    assert request.fabric_scope.epoch == request.id and request.fabric_scope.fabric_id == request.id
    assert request.fabric_scope.root_public_key == <<4>> <> :binary.copy(<<255>>, 64)
    assert request.fabric_scope.noc_sha256 == :binary.copy(<<255>>, 32)

    assert {:ok, %{principal: %{auth_mode: :group, subject: 0}}} =
             frame
             |> put_in(["principal", "auth_mode"], "group")
             |> put_in(["principal", "subject"], "0")
             |> decode()
  end

  test "read and invoke retain their selected flags while refusing foreign cells" do
    read =
      BridgeWireFixture.frame()
      |> put_in(["flags", "expanded"], true)
      |> put_in(["flags", "fabric_filtered"], true)
      |> put_in(["flags", "allows_large_payload"], true)

    assert {:ok, %{flags: %{expanded: true, fabric_filtered: true, allows_large_payload: true}}} =
             decode(read)

    refused(put_in(read, ["flags", "timed"], true))
    invoke = BridgeWireFixture.frame("invoke") |> put_in(["flags", "timed"], true)
    assert {:ok, %{flags: %{timed: true}, payload: {:tlv, <<21, 24>>}}} = decode(invoke)

    for flag <- ~w(expanded fabric_filtered allows_large_payload),
        do: refused(put_in(invoke, ["flags", flag], true))

    for flag <- ~w(expanded timed fabric_filtered allows_large_payload),
        do: refused(put_in(read, ["flags", flag], 1))

    refused(Map.put(read, "flags", []))
    refused(Map.put(invoke, "data_version", 0))
    refused(Map.put(read, "data_version", 0))
  end

  test "all finite scalar writes preserve null, defined enum values and uint16 endpoints" do
    base =
      BridgeWireFixture.frame("write")
      |> put_in(["flags", "expanded"], true)
      |> put_in(["flags", "timed"], true)
      |> Map.put("data_version", 0xFFFFFFFF)

    for {cluster, member} <- [{3, 0}, {6, 0x4001}, {6, 0x4002}], value <- [0, 65_535] do
      frame =
        base
        |> Map.put("path", %{"endpoint" => 65_534, "cluster" => cluster, "member" => member})
        |> Map.put("payload", %{"kind" => "u16", "value" => value})

      assert {:ok, %{operation: :write, payload: {:u16, ^value}, data_version: 0xFFFFFFFF}} =
               decode(frame)

      for invalid <- [-1, 65_536, nil, 1.0, "1"],
          do: refused(put_in(frame, ["payload", "value"], invalid))
    end

    for value <- [nil, 0, 1, 2] do
      frame =
        base
        |> put_in(["path", "member"], 0x4003)
        |> Map.put("payload", %{"kind" => "nullable_enum8", "value" => value})

      assert {:ok, %{payload: {:nullable_enum8, ^value}}} = decode(frame)
      for invalid <- [-1, 3, 0.0, "0"], do: refused(put_in(frame, ["payload", "value"], invalid))
    end

    valid =
      base
      |> put_in(["path", "member"], 0x4001)
      |> Map.put("payload", %{"kind" => "u16", "value" => 1})

    for flag <- ~w(fabric_filtered allows_large_payload),
        do: refused(put_in(valid, ["flags", flag], true))

    for version <- [-1, 0x100000000, 1.0, "1"], do: refused(Map.put(valid, "data_version", version))
    refused(put_in(valid, ["path", "member"], 1))
    refused(put_in(valid, ["payload", "kind"], "unknown"))
    refused(Map.put(valid, "payload", nil))
  end

  test "every object rejects missing, extra and duplicate members" do
    frame = BridgeWireFixture.frame()
    for key <- Map.keys(frame), do: refused(Map.delete(frame, key))
    refused(Map.put(frame, "extra", 1))

    for key <- ~w(path principal fabric_scope flags list) do
      for member <- Map.keys(frame[key]),
          do: refused(Map.update!(frame, key, &Map.delete(&1, member)))

      refused(Map.update!(frame, key, &Map.put(&1, "extra", 1)))
      refused(Map.put(frame, key, nil))
    end

    for operation <- ~w(write invoke) do
      current =
        BridgeWireFixture.frame(operation)
        |> Map.put("payload", %{"kind" => "tlv", "value" => "1518"})

      for key <- ~w(kind value), do: refused(Map.update!(current, "payload", &Map.delete(&1, key)))
      refused(Map.update!(current, "payload", &Map.put(&1, "extra", 1)))
    end

    raw = BridgeWireFixture.encode(frame)

    for field <- ["v", "generation", "id"] do
      duplicated =
        String.replace_prefix(raw, "{", "{#{Jason.encode!(field)}:#{Jason.encode!(frame[field])},")

      assert {:error, %Error{code: :invalid_frame}} =
               Wire.decode_request(duplicated, BridgeWireFixture.generation())
    end

    nested =
      String.replace(raw, "\"fabric_index\":254", "\"fabric_index\":254,\"fabric_index\":254")

    assert {:error, %Error{code: :invalid_frame}} =
             Wire.decode_request(nested, BridgeWireFixture.generation())
  end

  test "roles, generations and decimal uint64 identities are strict" do
    frame = BridgeWireFixture.frame()

    for {key, value} <- [
          {"v", 1.0},
          {"v", 2},
          {"backend", "matter"},
          {"type", "result"},
          {"operation", "subscribe"},
          {"generation", String.duplicate("F", 32)},
          {"generation", String.duplicate("00", 16)}
        ],
        do: refused(Map.put(frame, key, value))

    for key <- ~w(id deadline_ms),
        value <- ["0", "01", "+1", "-1", " 1", "1 ", "1.0", "18446744073709551616", 1, nil, []] do
      refused(Map.put(frame, key, value))
    end

    for key <- ~w(epoch fabric_id bridge_node),
        value <- ["0", "01", "-1", "18446744073709551616", 1],
        do: refused(put_in(frame, ["fabric_scope", key], value))

    refused(put_in(frame, ["fabric_scope", "bridge_node"], "18446744073709551615"))

    for value <- ["00", "-1", "18446744073709551616", 0, nil],
        do: refused(put_in(frame, ["principal", "subject"], value))

    assert {:ok, %{id: 1, deadline_native_ms: 1}} =
             frame
             |> Map.put("id", "1")
             |> Map.put("deadline_ms", "1")
             |> decode()
  end

  test "SDK identifier widths and reserved cells agree with the selected path profile" do
    read = BridgeWireFixture.frame()

    for {cluster, member} <- [
          {0, 0},
          {0x7FFF, 0xFFFE},
          {0x0001FC00, 0x00014FFF},
          {0xFFF4FFFE, 0xFFF44FFF}
        ] do
      assert {:ok, _} =
               read
               |> put_in(["path", "cluster"], cluster)
               |> put_in(["path", "member"], member)
               |> decode()
    end

    for {key, invalid} <- [
          {"endpoint", 2},
          {"endpoint", 65_535},
          {"endpoint", 3.0},
          {"cluster", 0x8000},
          {"cluster", 0xFC00},
          {"cluster", 0x00018000},
          {"cluster", 0xFFF5FC00},
          {"member", 0x5000},
          {"member", 0x0001F000},
          {"member", 0xFFFF},
          {"member", 0xFFF54FFF},
          {"member", nil}
        ] do
      refused(put_in(read, ["path", key], invalid))
    end

    invoke = BridgeWireFixture.frame("invoke")

    assert {:ok, _} =
             invoke
             |> put_in(["path", "member"], 0xFFF400FF)
             |> decode()

    for invalid <- [256, 0xFFF50000, -1, "1"],
        do: refused(put_in(invoke, ["path", "member"], invalid))
  end

  test "principal and fabric snapshot fields retain bounds without accepting unsupported auth modes" do
    frame = BridgeWireFixture.frame()

    for {key, value} <- [
          {"fabric_index", 0},
          {"fabric_index", 255},
          {"fabric_index", 1.0},
          {"auth_mode", "pase"},
          {"auth_mode", "none"},
          {"auth_mode", "internal"},
          {"is_commissioning", 1},
          {"cats", []},
          {"cats", [0, 0]},
          {"cats", [0, 0, 0, 0]},
          {"cats", [-1, 0, 0]},
          {"cats", [0x100000000, 0, 0]},
          {"cats", [1.0, 0, 0]}
        ],
        do: refused(put_in(frame, ["principal", key], value))

    for {key, value} <- [
          {"root_public_key", String.duplicate("00", 65)},
          {"root_public_key", "04" <> String.duplicate("ff", 63)},
          {"noc_sha256", String.duplicate("ff", 33)},
          {"noc_sha256", String.duplicate("FF", 32)},
          {"noc_sha256", nil}
        ],
        do: refused(put_in(frame, ["fabric_scope", key], value))

    assert {:ok, _} =
             frame
             |> put_in(["principal", "fabric_index"], 1)
             |> put_in(["principal", "is_commissioning"], false)
             |> decode()
  end

  test "opaque Thing bytes and frame limits include the required LF" do
    frame = BridgeWireFixture.frame()

    assert {:ok, %{thing: thing}} =
             frame
             |> Map.put("thing", String.duplicate("ff", 256))
             |> decode()

    assert thing == :binary.copy(<<255>>, 256)

    for value <- ["", "0", String.duplicate("ff", 257), "FF", "gg", nil],
        do: refused(Map.put(frame, "thing", value))

    encoded = BridgeWireFixture.encode(frame)
    body = binary_part(encoded, 0, byte_size(encoded) - 1)
    maximum = body <> String.duplicate(" ", 262_143 - byte_size(body)) <> "\n"
    assert {:ok, _} = Wire.decode_request(maximum, BridgeWireFixture.generation())

    for invalid <- [
          body,
          body <> "\r\n",
          body <> <<0>> <> "\n",
          encoded <> "\n",
          "",
          "{}\n",
          <<255, 10>>,
          maximum <> "\n"
        ] do
      assert {:error, %Error{code: :invalid_frame}} =
               Wire.decode_request(invalid, BridgeWireFixture.generation())
    end

    for generation <- [nil, <<>>, :binary.copy(<<0>>, 15), :binary.copy(<<0>>, 17)],
        do:
          assert({:error, %Error{code: :invalid_frame}} = Wire.decode_request(encoded, generation))

    refused(put_in(frame, ["list", "operation"], "replace-all"))
    refused(put_in(frame, ["list", "index"], 0.0))
    refused(Map.put(frame, "payload", %{}))
  end

  test "invoke syntax scans preserve the full SDK byte, depth and node profile" do
    frame = BridgeWireFixture.frame("invoke")
    maximum = <<21, 49, 0, 65_530::little-16>> <> :binary.copy(<<255>>, 65_530) <> <<24>>
    deep = <<21>> <> :binary.copy(<<53, 0>>, 23) <> :binary.copy(<<24>>, 24)
    wide = <<21>> <> :binary.copy(<<41, 0>>, 4095) <> <<24>>

    for bytes <- [<<21, 24>>, maximum, deep, wide] do
      assert {:ok, %{payload: {:tlv, ^bytes}}} =
               frame
               |> Map.put("payload", BridgeWireFixture.arguments(bytes))
               |> decode()
    end

    for bytes <- [
          <<21>> <> :binary.copy(<<53, 0>>, 24) <> :binary.copy(<<24>>, 25),
          <<21>> <> :binary.copy(<<41, 0>>, 4096) <> <<24>>,
          maximum <> <<24>>,
          <<>>,
          <<20>>,
          <<21>>,
          <<53, 0, 24>>,
          <<21, 24, 20>>,
          <<21, 24, 24>>,
          <<21, 56>>,
          <<21, 25, 24>>,
          <<21, 32>>,
          <<21, 31, 24>>,
          <<21, 49, 0, 65_535::little-16, 24>>,
          <<21, 48, 0>>,
          <<21, 53, 0, 24>>
        ] do
      refused(Map.put(frame, "payload", BridgeWireFixture.arguments(bytes)))
    end

    for value <- ["1518F", "1518FF", nil, 1],
        do: refused(put_in(frame, ["payload", "value"], value))

    refused(put_in(frame, ["payload", "kind"], "bytes"))
  end

  test "opaque invoke syntax preserves scalar widths, tag widths and nested container kinds" do
    frame = BridgeWireFixture.frame("invoke")

    for {type, body} <- [
          {0, <<-1::signed-8>>},
          {1, <<-1::little-signed-16>>},
          {2, <<-1::little-signed-32>>},
          {3, <<-1::little-signed-64>>},
          {4, <<255>>},
          {5, <<65_535::little-16>>},
          {6, <<0xFFFFFFFF::little-32>>},
          {7, <<0xFFFFFFFFFFFFFFFF::little-64>>},
          {8, <<>>},
          {9, <<>>},
          {10, <<0::little-32>>},
          {11, <<0::little-64>>},
          {12, <<1, 97>>},
          {13, <<1::little-16, 97>>},
          {14, <<1::little-32, 97>>},
          {15, <<1::little-64, 97>>},
          {16, <<1, 255>>},
          {17, <<1::little-16, 255>>},
          {18, <<1::little-32, 255>>},
          {19, <<1::little-64, 255>>},
          {20, <<>>}
        ] do
      bytes = <<21, type + 32, 0>> <> body <> <<24>>

      assert {:ok, %{payload: {:tlv, ^bytes}}} =
               frame
               |> Map.put("payload", BridgeWireFixture.arguments(bytes))
               |> decode()

      if byte_size(body) > 0,
        do:
          refused(
            Map.put(
              frame,
              "payload",
              BridgeWireFixture.arguments(binary_part(bytes, 0, byte_size(bytes) - 2) <> <<24>>)
            )
          )
    end

    for {control, tag} <- [
          {32, <<0>>},
          {64, <<0::little-16>>},
          {96, <<0::little-32>>},
          {192, <<0::little-48>>},
          {224, <<0::little-64>>}
        ] do
      bytes = <<21, control + 20>> <> tag <> <<24>>

      assert {:ok, _} =
               frame
               |> Map.put("payload", BridgeWireFixture.arguments(bytes))
               |> decode()
    end

    for type <- [21, 22, 23] do
      bytes = <<21, type + 32, 0, 24, 24>>

      assert {:ok, _} =
               frame
               |> Map.put("payload", BridgeWireFixture.arguments(bytes))
               |> decode()
    end
  end

  test "invoke tags obey SDK Structure, Array, List and special profile rules" do
    frame = BridgeWireFixture.frame("invoke")
    anonymous = <<255, 255, 255, 255, 0, 1>>
    unknown = <<255, 255, 255, 255, 1, 1>>

    for bytes <- [
          <<21, 54, 0, 20, 21, 41, 0, 24, 24, 24>>,
          <<21, 55, 0, 20, 52, 0, 24, 24>>,
          <<21, 54, 0, 212>> <> anonymous <> <<24, 24>>,
          <<213>> <> anonymous <> <<24>>,
          <<21, 216>> <> anonymous,
          <<21, 244, 255, 255, 255, 255, 255, 255, 255, 255, 24>>
        ] do
      assert {:ok, %{payload: {:tlv, ^bytes}}} =
               frame
               |> Map.put("payload", BridgeWireFixture.arguments(bytes))
               |> decode()
    end

    for bytes <- [
          <<21, 20, 24>>,
          <<21, 54, 0, 52, 0, 24, 24>>,
          <<21, 55, 0, 148, 0, 0, 24, 24>>,
          <<21, 180, 0, 0, 0, 0, 24>>,
          <<21, 53, 0, 24, 20, 24>>,
          <<21, 212>> <> anonymous <> <<24>>,
          <<21, 212>> <> unknown <> <<24>>,
          <<21, 248, 255, 255, 255, 255, 0, 1, 0, 0, 24>>
        ],
        do: refused(Map.put(frame, "payload", BridgeWireFixture.arguments(bytes)))
  end

  test "consumer results match the exact bounded native result contract" do
    generation = BridgeWireFixture.generation()

    for outcome <- [:completed, :denied, :failed, :unknown], id <- [1, 0xFFFFFFFFFFFFFFFF] do
      assert {:ok, encoded} = Wire.encode_result(generation, id, outcome)
      assert byte_size(encoded) <= 512 and String.ends_with?(encoded, "\n")

      assert Jason.decode!(encoded) == %{
               "v" => 1,
               "backend" => "matter-bridge",
               "type" => "result",
               "generation" => Base.encode16(generation, case: :lower),
               "id" => Integer.to_string(id),
               "outcome" => Atom.to_string(outcome)
             }
    end

    for {generation, id, outcome} <- [
          {nil, 1, :completed},
          {<<>>, 1, :completed},
          {generation, 0, :completed},
          {generation, 0x10000000000000000, :completed},
          {generation, 1.0, :completed},
          {generation, "1", :completed},
          {generation, 1, "completed"},
          {generation, 1, :timeout}
        ] do
      assert {:error, %Error{code: :invalid_frame, details: %{}}} =
               Wire.encode_result(generation, id, outcome)
    end
  end

  property "bounded arbitrary bytes return a validated request or a structured error without external data" do
    check all(bytes <- binary(max_length: 2048)) do
      case Wire.decode_request(bytes <> "\n", BridgeWireFixture.generation()) do
        {:error, %Error{code: :invalid_frame, details: %{}}} -> :ok
        {:ok, request} -> assert(request.generation == BridgeWireFixture.generation())
      end
    end
  end
end
