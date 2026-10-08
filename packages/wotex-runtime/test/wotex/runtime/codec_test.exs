defmodule Wotex.Runtime.CodecTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Runtime.{Codec, Context}
  alias Wotex.Runtime.Codec.{Call, Result, Value}
  alias Wotex.Runtime.Implementation.{Admission, Error, Plan}
  alias Wotex.Runtime.TestSupport.CodecExecutor, as: Executor
  alias Wotex.Runtime.TestSupport.ImplementationFactory, as: F

  test "all inert node forms encode exactly, preserving missing/null/empty and full integers" do
    nodes = [
      null(),
      %{"type" => "boolean", "value" => true},
      text("\u0000é"),
      %{"type" => "bytes", "base64" => "AQ=="},
      sint("-9223372036854775808"),
      sint("9223372036854775807"),
      uint("18446744073709551615"),
      %{"type" => "decimal", "coefficient" => "123", "exponent" => -2},
      list([]),
      object([])
    ]

    for node <- nodes do
      assert {:ok, ^node} = Value.validate(node)
      assert {:ok, encoded} = Value.encode(node)
      assert Jason.decode!(encoded) == node
    end

    assert Value.encode(sint("-9223372036854775808")) ==
             {:ok, ~s({"type":"sint","value":"-9223372036854775808"})}

    assert {:ok, ~s({"type":"text","value":"\\u0000é"})} = Value.encode(text("\u0000é"))
    distinct = [null(), text(""), %{"type" => "bytes", "base64" => ""}, uint("0"), object([])]
    assert length(Enum.uniq(Enum.map(distinct, &Value.encode/1))) == 5
    ordered = object([{"a", null()}, {"\uE000", uint("1")}, {"\u{10000}", uint("2")}])
    assert {:ok, ^ordered} = Value.validate(ordered)

    assert {:error, %Error{code: :unsupported_value}} =
             Value.validate(object([{"\u{10000}", null()}, {"\uE000", null()}]))
  end

  test "closed algebra rejects coercions, noncanonical integers, decimals, Base64 and objects" do
    bad = [
      nil,
      1,
      1.0,
      :nan,
      %{},
      %{type: "null"},
      %{"type" => "null", "extra" => "canary"},
      %{"type" => "boolean", "value" => 1},
      text(<<255>>),
      sint("+1"),
      sint("-0"),
      sint("01"),
      sint("9223372036854775808"),
      sint("-9223372036854775809"),
      uint("-1"),
      uint("18446744073709551616"),
      sint(String.duplicate("9", 21)),
      sint(1),
      %{"type" => "decimal", "coefficient" => "10", "exponent" => 0},
      %{"type" => "decimal", "coefficient" => "0", "exponent" => 1},
      %{"type" => "decimal", "coefficient" => "1", "exponent" => 32_768},
      %{"type" => "decimal", "coefficient" => "1", "exponent" => -32_769},
      %{"type" => "decimal", "coefficient" => "1", "exponent" => 1.0},
      object([{"a", null()}, {"a", null()}]),
      object([{"b", null()}, {"a", null()}]),
      object([{"", null()}]),
      object([{String.duplicate("k", 129), null()}]),
      object([{<<255>>, null()}]),
      %{"type" => "object", "entries" => [%{"key" => "a", "value" => null(), "extra" => 1}]},
      %{"type" => "object", "entries" => [null()]},
      %{"type" => "list", "items" => [null() | :bad]},
      %{"type" => "list", "items" => :bad}
    ]

    for node <- bad do
      assert {:error, %Error{code: :unsupported_value} = error} = Value.encode(node)
      refute inspect(error) =~ "canary"
    end

    for base64 <- ["AR==", "AQ", "AQ=", "AQ===", " A Q==", "AQ==\n", "_w==", "A===", 1] do
      assert {:error, %Error{code: :unsupported_value}} =
               Value.validate(%{"type" => "bytes", "base64" => base64})
    end

    for exponent <- [-32_768, 32_767], coefficient <- ["-1", "1"] do
      assert {:ok, _} =
               Value.validate(%{
                 "type" => "decimal",
                 "coefficient" => coefficient,
                 "exponent" => exponent
               })
    end

    assert {:ok, _} = Value.validate(%{"type" => "decimal", "coefficient" => "0", "exponent" => 0})
  end

  test "typed depth, nodes, collection, text, decoded bytes and encoded output obey equality bounds" do
    for node <- [
          text(String.duplicate("a", 4096)),
          %{"type" => "bytes", "base64" => Base.encode64(:binary.copy(<<0>>, 4096))},
          list(List.duplicate(null(), 256)),
          nested(8),
          list(Enum.map([256, 256, 256, 251], &list(List.duplicate(null(), &1))))
        ] do
      assert {:ok, _} = Value.validate(node)
    end

    for node <- [
          text(String.duplicate("a", 4097)),
          %{"type" => "bytes", "base64" => Base.encode64(:binary.copy(<<0>>, 4097))},
          %{"type" => "bytes", "base64" => String.duplicate("A", 5465)},
          list(List.duplicate(null(), 257)),
          nested(9),
          list(Enum.map([256, 256, 256, 252], &list(List.duplicate(null(), &1))))
        ] do
      assert {:error, %Error{code: :output_limit}} = Value.validate(node)
    end

    prefix = List.duplicate(text(String.duplicate("a", 4096)), 15)
    {:ok, base} = Value.encode(list([text("") | prefix]))
    padding = 65_536 - byte_size(base)
    assert padding in 1..4096
    exact = list([text(String.duplicate("a", padding)) | prefix])
    assert {:ok, bytes} = Value.encode(exact)
    assert byte_size(bytes) == 65_536

    assert {:error, %Error{code: :output_limit}} =
             Value.encode(list([text(String.duplicate("a", padding + 1)) | prefix]))

    escaped = text(String.duplicate(<<0>>, 4096))
    assert {:ok, _} = Value.encode(escaped)
    assert {:error, %Error{code: :output_limit}} = Value.encode(list(List.duplicate(escaped, 3)))
  end

  test "facade admits before exactly one callback and derives every result identity" do
    plan = F.plan(%{"offset" => -1})
    ctx = context()
    owner = self()

    decode = fn input, metadata, call ->
      send(owner, {:called, input, metadata, call.plan.configuration})
      Result.new(uint("1"), call)
    end

    assert {:ok, result} =
             Codec.decode(plan, <<1>>, %{"format" => "uint8"}, ctx, {Executor, decode})

    assert_receive {:called, <<1>>, %{"format" => "uint8"}, %{"offset" => -1}}
    refute_receive {:called, _, _, _}
    assert result.request_id == ctx.request_id
    assert result.descriptor_sha256 == plan.admission.descriptor.sha256
    assert result.deployment == plan.admission.value["deployment"]
    assert result.contract_id == "example.uint8" and result.contract_sha256 == F.hash("c")
    assert result.configuration_sha256 == plan.configuration_sha256

    assert result.binding == plan.admission.descriptor.value["binding"] and
             result.instance_key == plan.instance_key

    {:ok, call} = Call.new(plan, ctx)
    assert Call.validate(call) == :ok
    assert Result.validate(result, call) == :ok

    for field <- [
          :descriptor_sha256,
          :deployment,
          :contract_id,
          :contract_sha256,
          :configuration_sha256,
          :binding,
          :instance_key,
          :request_id
        ] do
      forged = Map.put(result, field, nil)

      assert {:error, %Error{code: :correlation_failed}} =
               Codec.decode(plan, <<1>>, %{}, ctx, {Executor, fn _, _, _ -> {:ok, forged} end})
    end

    for bad <- [nil, %{__struct__: Call}, Map.put(call, :extra, 1)] do
      assert {:error, %Error{}} = Call.validate(bad)
      assert {:error, %Error{}} = Result.new(null(), bad)
    end

    assert {:error, %Error{}} = Result.validate(%{__struct__: Result}, call)
    assert {:error, %Error{}} = Result.validate(nil, call)
  end

  test "flat metadata and configuration, context and profile refusals invoke no callback" do
    owner = self()

    executor =
      {Executor,
       fn _, _, call ->
         send(owner, :called)
         Result.new(null(), call)
       end}

    plan = F.plan()

    for input <- [:bad, :binary.copy(<<0>>, 65_537)] do
      assert {:error, %Error{code: :invalid_input}} =
               Codec.decode(plan, input, %{}, context(), executor)
    end

    for metadata <- [
          nil,
          %{atom: 1},
          %{"k" => %{}},
          %{"k" => []},
          %{"k" => 1.0},
          %{"k" => 9_007_199_254_740_992},
          %{String.duplicate("k", 129) => 1},
          %{"k" => String.duplicate("v", 257)},
          %{"k" => <<255>>},
          Map.new(1..17, &{Integer.to_string(&1), nil})
        ] do
      assert {:error, %Error{code: :invalid_metadata}} =
               Codec.decode(plan, <<>>, metadata, context(), executor)
    end

    for configuration <- [
          %{"k" => []},
          %{"k" => String.duplicate("v", 257)},
          Map.new(1..17, &{Integer.to_string(&1), nil})
        ] do
      assert {:error, %Error{code: :invalid_configuration}} =
               Codec.decode(F.plan(configuration), <<>>, %{}, context(), executor)
    end

    for ctx <- [
          nil,
          %{__struct__: Context},
          %{context() | request_id: ""},
          %{context() | deadline: :bad}
        ] do
      assert {:error, %Error{}} = Codec.decode(plan, <<>>, %{}, ctx, executor)
    end

    for {key, replacement, code} <- [
          {"api", %{"id" => "wotex.codec", "version" => "2.0.0"}, :incompatible_api},
          {"binding", %{"id" => "beam-codec", "version" => "2.0.0"}, :incompatible_binding}
        ] do
      d = F.descriptor(Map.put(F.descriptor_map(), key, replacement))
      {:ok, admission} = Admission.new(d, F.inputs(d))
      {:ok, p} = Plan.new(admission, %{}, F.key(), fn _, _ -> :ok end)
      assert {:error, %Error{code: ^code}} = Codec.decode(p, <<>>, %{}, context(), executor)
    end

    refute_receive :called
    assert {:error, %Error{}} = Codec.decode(plan, <<>>, %{}, context(), nil)

    for metadata <- [
          %{"k" => -9_007_199_254_740_991},
          %{"k" => nil},
          %{"k" => true},
          %{"k" => String.duplicate("v", 256)},
          %{String.duplicate("k", 128) => ""}
        ] do
      assert {:ok, _} =
               Codec.decode(plan, :binary.copy(<<0>>, 65_536), metadata, context(), executor)

      assert_receive :called
    end

    assert {:ok, _} = Call.new(plan, context(DateTime.utc_now()))
    assert {:ok, _} = Call.new(plan, context(nil))
  end

  test "executor exceptions, malformed returns and forged output are fixed and redact canaries" do
    plan = F.plan(%{"value" => "configuration-canary"})
    ctx = context()

    callbacks = [
      fn _, _, _ -> raise "exception-canary" end,
      fn _, _, _ -> exit("exit-canary") end,
      fn _, _, _ -> throw("throw-canary") end
    ]

    for callback <- callbacks do
      assert {:error, %Error{code: :codec_unavailable} = error} =
               Codec.decode(
                 plan,
                 "input-canary",
                 %{"key" => "metadata-canary"},
                 ctx,
                 {Executor, callback}
               )

      refute inspect(error) =~ "canary"
    end

    for returned <- [
          nil,
          {:ok, null()},
          {:error, :invalid_input},
          {:error, %Error{code: :invalid_input, class: :foreign}},
          {:ok, %{__struct__: Result}}
        ] do
      assert {:error, %Error{} = error} =
               Codec.decode(plan, <<>>, %{}, ctx, {Executor, fn _, _, _ -> returned end})

      refute inspect(error) =~ "canary"
    end

    assert {:error, %Error{code: :invalid_input}} =
             Codec.decode(
               plan,
               <<>>,
               %{},
               ctx,
               {Executor, fn _, _, _ -> {:error, Error.new(:invalid_input, :decode, %{})} end}
             )

    {:ok, call} = Call.new(plan, ctx)
    {:ok, result} = Result.new(text("output-canary"), call)
    refute inspect(plan) =~ "configuration-canary"
    refute inspect(call) =~ "configuration-canary"
    refute inspect(result) =~ "output-canary"

    assert {:error, %Error{code: :protocol_fault}} =
             Codec.decode(
               plan,
               <<>>,
               %{},
               ctx,
               {Executor, fn _, _, _ -> {:ok, %{result | value: %{}}} end}
             )
  end

  test "canonical metadata and configuration size admit equality and refuse one byte over" do
    base =
      Map.new(1..15, fn index ->
        {"m" <> String.pad_leading(Integer.to_string(index), 2, "0"), String.duplicate("v", 256)}
      end)

    base = Map.put(base, "m16", "")
    padding = 4096 - byte_size(Jason.encode!(base))
    assert padding in 1..256
    exact = Map.put(base, "m16", String.duplicate("v", padding))
    over = Map.put(base, "m16", String.duplicate("v", padding + 1))
    assert byte_size(Jason.encode!(exact)) == 4096
    executor = {Executor, fn _, _, call -> Result.new(null(), call) end}
    assert {:ok, _} = Codec.decode(F.plan(exact), <<>>, exact, context(), executor)

    assert {:error, %Error{code: :invalid_metadata}} =
             Codec.decode(F.plan(), <<>>, over, context(), executor)

    assert {:error, %Error{code: :invalid_configuration}} =
             Codec.decode(F.plan(over), <<>>, %{}, context(), executor)
  end

  defp context(deadline \\ 10_000),
    do: Context.new!(request_id: "codec-request", deadline: deadline)

  defp null, do: %{"type" => "null"}
  defp text(v), do: %{"type" => "text", "value" => v}
  defp sint(v), do: %{"type" => "sint", "value" => v}
  defp uint(v), do: %{"type" => "uint", "value" => v}
  defp list(items), do: %{"type" => "list", "items" => items}

  defp object(entries),
    do: %{
      "type" => "object",
      "entries" => Enum.map(entries, fn {k, v} -> %{"key" => k, "value" => v} end)
    }

  defp nested(1), do: null()
  defp nested(depth), do: list([nested(depth - 1)])
end
