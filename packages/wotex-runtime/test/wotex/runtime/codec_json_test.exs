defmodule Wotex.Runtime.CodecJSONTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Runtime.{Codec, Context}
  alias Wotex.Runtime.Codec.{Beam, JSON, Value}
  alias Wotex.Runtime.Implementation.{Admission, Error, Inputs, Plan, Registration}
  alias Wotex.Runtime.TestSupport.ImplementationFactory, as: F

  @corpus __DIR__
          |> Path.join("../../support/codec_json_vectors.json")
          |> File.read!()
          |> Jason.decode!()

  test "independent literal JSON inputs match complete typed and canonical expected values" do
    for row <- @corpus["cases"] do
      if Map.has_key?(row, "expected") do
        assert {:ok, value} = JSON.decode(row["input"]), row["id"]
        assert value == row["expected"], row["id"]
        assert {:ok, value} == Value.validate(value)
        assert {:ok, row["canonical"]} == Value.encode(value)

        assert :crypto.hash(:sha256, row["canonical"]) |> Base.encode16(case: :lower) ==
                 row["sha256"]

        assert JSON.decode(row["input"], %{}, %{}) == {:ok, value}
      else
        assert {:error, String.to_existing_atom(row["error"])} == JSON.decode(row["input"]),
               row["id"]
      end
    end
  end

  test "typed depth includes primitive children and empty container boundaries" do
    assert {:ok, _} = JSON.decode(String.duplicate("[", 8) <> String.duplicate("]", 8))
    assert {:ok, _} = JSON.decode(String.duplicate("[", 7) <> "1" <> String.duplicate("]", 7))

    assert {:error, :output_limit} =
             JSON.decode(String.duplicate("[", 8) <> "1" <> String.duplicate("]", 8))
  end

  test "member, node and text ceilings admit equality and refuse one more" do
    assert {:ok, _} = JSON.decode("[" <> Enum.map_join(1..256, ",", fn _ -> "0" end) <> "]")
    assert {:ok, _} = JSON.decode(Jason.encode!(String.duplicate("é", 2048)))
    assert {:error, :output_limit} = JSON.decode(Jason.encode!(String.duplicate("é", 2049)))
    # root + four inner collections + 1019 scalars = 1024 typed nodes.
    values = [
      List.duplicate(0, 256),
      List.duplicate(0, 256),
      List.duplicate(0, 256),
      List.duplicate(0, 251)
    ]

    assert {:ok, _} = JSON.decode(Jason.encode!(values))

    assert {:error, :output_limit} =
             JSON.decode(Jason.encode!(List.update_at(values, 3, &[0 | &1])))

    assert {:ok, _} = JSON.decode(Jason.encode!(%{String.duplicate("k", 128) => "value"}))

    for key <- [String.duplicate("k", 129), String.duplicate("k", 4097)] do
      assert {:error, :unsupported_value} = JSON.decode(Jason.encode!(%{key => 1}))
    end
  end

  test "input and numeric token ceilings are checked before conversion" do
    assert {:ok, _} = JSON.decode("1" <> String.duplicate(" ", 65_535))
    assert {:error, :output_limit} = JSON.decode("1" <> String.duplicate(" ", 65_536))
    token = "0." <> String.duplicate("0", 125) <> "1"
    assert byte_size(token) == 128
    assert {:ok, %{"coefficient" => "1", "exponent" => -126}} = JSON.decode(token)
    assert {:error, :output_limit} = JSON.decode(token <> "0")
    exponent_only = "1e" <> String.duplicate("0", 126)
    assert byte_size(exponent_only) == 128
    assert {:ok, %{"coefficient" => "1", "exponent" => 0}} = JSON.decode(exponent_only)
    assert {:error, :output_limit} = JSON.decode(exponent_only <> "0")
    text = "\"\\" <> String.duplicate("1", 129)
    assert {:ok, %{"type" => "text", "value" => ^text}} = JSON.decode(Jason.encode!(text))
    assert {:error, :invalid_input} = JSON.decode(<<255>>)
    assert {:error, :invalid_input} = JSON.decode(<<34, 0, 34>>)
  end

  test "escaped continuations retain refusals and maximum grammar nesting retains no typed tree" do
    for prefix <- ["[1.0,", "[\"\\u0061\","] do
      assert {:error, :output_limit} =
               JSON.decode(
                 prefix <>
                   String.duplicate("[", 9) <>
                   String.duplicate("]", 9) <> "]"
               )
    end

    for input <- ["[1e32768]", "{\"x\":1e32768}", "[1e32768,2]", "{\"x\":1e32768,\"y\":2}"] do
      assert {:error, :unsupported_value} = JSON.decode(input)
    end

    assert {:error, :output_limit} =
             JSON.decode(
               String.duplicate("[", 32_768) <>
                 String.duplicate("]", 32_768)
             )
  end

  test "canonical output byte ceiling admits equality and refuses one more" do
    # Independent literal wire construction; never allocate expectations with Value.encode.
    text = fn value -> ~s({"type":"text","value":"#{value}"}) end
    wire = fn values -> ~s({"items":[#{Enum.map_join(values, ",", text)}],"type":"list"}) end
    values = ["" | List.duplicate(String.duplicate("x", 4096), 15)]
    padding = 65_536 - byte_size(wire.(values))
    assert padding in 1..4096
    exact = List.replace_at(values, 0, String.duplicate("x", padding))
    assert {:ok, value} = JSON.decode(Jason.encode!(exact))
    assert {:ok, expected} = Value.encode(value)
    assert expected == wire.(exact)
    assert byte_size(expected) == 65_536
    over = List.update_at(exact, 0, &(&1 <> "x"))
    assert {:error, :output_limit} = JSON.decode(Jason.encode!(over))
  end

  test "output expansion retains the existing canonical Value byte ceiling" do
    # 256 text nodes: JSON fits, but the C02 wrappers cannot fit its wire ceiling.
    input = Jason.encode!(List.duplicate(String.duplicate("x", 240), 256))
    assert byte_size(input) <= 65_536
    assert {:error, :output_limit} = JSON.decode(input)
  end

  test "wrong API metadata/configuration and native values return only fixed atoms" do
    for input <- [nil, true, 1, 1.0, %{}, [], :json, ""] do
      assert {:error, :invalid_input} = JSON.decode(input)
    end

    for value <- [%{"private-canary" => "secret"}, [], nil, 0, MapSet.new()] do
      assert {:error, :unsupported_format} = JSON.decode("1", value, %{})
      assert {:error, :unsupported_format} = JSON.decode("1", %{}, value)
    end

    assert {:error, :invalid_input} = JSON.decode("{\"private-canary\":")
    assert {:error, :invalid_input} = JSON.decode(~s({"a":1,"\\u0061":2}))
  end

  test "registered BEAM execution preserves exact values, identity and refusal codes" do
    descriptor = F.descriptor()
    inputs = F.inputs(descriptor)
    contract = %{"id" => "example.exact-json", "version" => "1.0.0", "sha256" => F.hash("d")}

    {:ok, registration} =
      Registration.new(
        Map.put(inputs.registrations["example.codec"].value, "codec_contract", contract)
      )

    {:ok, inputs} =
      Inputs.new(
        Map.put(Map.from_struct(inputs), :registrations, %{"example.codec" => registration})
      )

    {:ok, admission} = Admission.new(descriptor, inputs)
    {:ok, plan} = Plan.new(admission, %{}, F.key(), fn _, _ -> :ok end)
    supervisor = start_supervised!({Task.Supervisor, max_children: 1})

    config = %{
      decoder: JSON,
      contract: contract,
      task_supervisor: supervisor,
      current_inputs: fn -> inputs end,
      now: fn -> System.monotonic_time(:millisecond) end
    }

    context = Context.new!(request_id: "json-request")
    assert {:ok, result} = Codec.decode(plan, "9007199254740993.1", %{}, context, {Beam, config})

    assert result.value == %{
             "type" => "decimal",
             "coefficient" => "90071992547409931",
             "exponent" => -1
           }

    assert result.request_id == "json-request"
    assert result.contract_id == contract["id"]
    assert result.contract_sha256 == contract["sha256"]
    assert result.instance_key == plan.instance_key

    for {input, code} <- [
          {"1e32768", :unsupported_value},
          {"[1,]", :invalid_input},
          {"0." <> String.duplicate("0", 127), :output_limit}
        ] do
      assert {:error, %Error{code: ^code}} = Codec.decode(plan, input, %{}, context, {Beam, config})
    end

    assert {:error, %Error{code: :unsupported_format}} =
             Codec.decode(plan, "1", %{"format" => "json"}, context, {Beam, config})

    assert Task.Supervisor.children(supervisor) == []
  end

  test "repeated independent processes give identical values" do
    input = "{\"precise\":9007199254740993.1,\"null\":null,\"state\":false}"
    expected = JSON.decode(input)
    assert {:ok, _} = expected

    for result <- Task.async_stream(1..16, fn _ -> JSON.decode(input) end, max_concurrency: 4),
        do: assert(result == {:ok, expected})
  end
end
