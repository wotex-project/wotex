defmodule Wotex.AdmissionSafetyTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.{
    ActionAffordance,
    DataSchema,
    Error,
    EventAffordance,
    Form,
    JSON,
    PropertyAffordance,
    SecurityScheme,
    ThingDescription,
    ThingModel
  }

  @extension_key "x-example:温度/key~"
  @extension_value %{"label/key~" => ["å", "é", "𝄞"]}

  test "both aggregates preserve Unicode extensions at exact admission thresholds" do
    for aggregate <- aggregate_cases() do
      document = aggregate.document
      {nodes, bytes, depth} = metrics(document)
      json = Jason.encode!(document)

      assert {:ok, value} = aggregate.from_map.(document, [])
      assert aggregate.to_map.(value) == document

      assert {:ok, _} =
               aggregate.from_map.(document, threshold_options(nodes, bytes, depth))

      assert {:error, %Error{code: :byte_limit_exceeded}} =
               aggregate.from_map.(document, max_bytes: bytes - 1)

      assert {:error, %Error{code: :depth_limit_exceeded}} =
               aggregate.from_map.(document, max_depth: depth - 1)

      assert {:error, %Error{code: :node_limit_exceeded}} =
               aggregate.from_map.(document, max_nodes: nodes - 1)

      assert {:ok, _} = aggregate.parse.(json, max_bytes: byte_size(json))

      assert {:error, %Error{code: :byte_limit_exceeded, phase: :parse}} =
               aggregate.parse.(json, max_bytes: byte_size(json) - 1)
    end
  end

  test "every wrapper preserves Unicode extensions at exact admission thresholds" do
    for wrapper <- wrapper_cases() do
      document = wrapper.document
      {nodes, bytes, depth} = metrics(document)

      assert {:ok, value} = wrapper.new.(document, [])
      assert wrapper.to_map.(value) == document

      assert {:ok, _} = wrapper.new.(document, threshold_options(nodes, bytes, depth))

      assert {:error, %Error{code: :byte_limit_exceeded}} =
               wrapper.new.(document, max_bytes: bytes - 1)

      assert {:error, %Error{code: :depth_limit_exceeded}} =
               wrapper.new.(document, max_depth: depth - 1)

      assert {:error, %Error{code: :node_limit_exceeded}} =
               wrapper.new.(document, max_nodes: nodes - 1)
    end
  end

  test "aggregate and wrapper paths escape extension terms without copying invalid bytes" do
    expected_value_path = "/x~1example~0/value~1key~0"
    expected_key_path = "/x~1example~0"

    for aggregate <- aggregate_cases() do
      assert {:error, %Error{code: :invalid_string, path: ^expected_value_path}} =
               aggregate.from_map.(invalid_extension_value(aggregate.document), [])

      assert {:error, %Error{code: :invalid_string, path: ^expected_key_path} = error} =
               aggregate.from_map.(invalid_extension_key(aggregate.document), [])

      assert String.valid?(error.path)
    end

    for wrapper <- wrapper_cases() do
      assert {:error, %Error{code: :invalid_string, path: ^expected_value_path}} =
               wrapper.new.(invalid_extension_value(wrapper.document), [])

      assert {:error, %Error{code: :invalid_string, path: ^expected_key_path} = error} =
               wrapper.new.(invalid_extension_key(wrapper.document), [])

      assert String.valid?(error.path)
    end
  end

  test "all option-bearing admission operations refuse malformed containers" do
    malformed_options = [:invalid, [:invalid], [{"max_nodes", 2}], [{:max_nodes, 2} | :tail]]

    for opts <- malformed_options,
        aggregate <- aggregate_cases() do
      document = aggregate.document
      json = Jason.encode!(document)
      assert_invalid_options(aggregate.parse.(json, opts))
      assert_invalid_options(aggregate.from_map.(document, opts))
      assert {:ok, value} = aggregate.from_map.(document, [])
      assert_invalid_options(aggregate.validate.(value, opts))
      assert_invalid_options(aggregate.put_id.(value, "urn:example:changed", opts))
      raised = assert_raise Error, fn -> aggregate.parse_bang.(json, opts) end
      assert raised.code == :invalid_options
      assert raised.phase == :value
    end

    for opts <- malformed_options,
        wrapper <- wrapper_cases() do
      assert_invalid_options(wrapper.new.(wrapper.document, opts))
    end

    for opts <- malformed_options do
      assert_invalid_options(JSON.decode("{}", opts))
      assert_invalid_options(JSON.validate(%{}, opts))
      assert_invalid_options(JSON.encode(%{}, opts))
      assert_invalid_options(Wotex.JSON.Limits.new(opts))
    end
  end

  test "staged aggregate parsing retains JSON admission and requires explicit validation" do
    for aggregate <- aggregate_cases() do
      json = Jason.encode!(%{@extension_key => @extension_value})

      assert {:ok, value} = aggregate.parse.(json, validate: false)
      assert aggregate.to_map.(value) == %{@extension_key => @extension_value}
      assert {:ok, ^json} = aggregate.encode.(value, :source)
      assert {:error, errors} = aggregate.validate.(value, [])
      assert is_list(errors) and errors != []

      assert {:error, %Error{code: :node_limit_exceeded}} =
               aggregate.parse.(json, validate: false, max_nodes: 1)
    end
  end

  test "both aggregate parsers reject nested duplicate members at escaped paths" do
    for aggregate <- aggregate_cases() do
      json = ~S({"x/example~":{"member":1,"member":2}})

      assert {:error, %Error{code: :duplicate_member, phase: :parse, path: path}} =
               aggregate.parse.(json, [])

      assert path == "/x~1example~0/member"
    end
  end

  test "aggregate and wrapper constructors reject Elixir structs at the JSON boundary" do
    non_json = URI.parse("https://example.com/thing")

    for aggregate <- aggregate_cases() do
      assert {:error, %Error{code: :invalid_json_value, path: "/"}} =
               aggregate.from_map.(non_json, [])
    end

    for wrapper <- wrapper_cases() do
      assert {:error, %Error{code: :invalid_json_value, path: "/"}} =
               wrapper.new.(non_json, [])
    end
  end

  test "diagnostic representations are bounded and schema errors omit rejected values" do
    private_value = String.duplicate("credential-canary-", 100)

    assert {:error, %Error{details: %{value: rendered_limit}}} =
             JSON.validate(%{}, max_nodes: private_value)

    assert rendered_limit =~ "credential-canary-"
    refute rendered_limit =~ private_value
    assert byte_size(rendered_limit) < byte_size(private_value)

    assert {:error, %Error{details: %{key: rendered_key}}} =
             JSON.validate(%{{:invalid, private_value} => true})

    assert rendered_key =~ "credential-canary-"
    refute rendered_key =~ private_value
    assert byte_size(rendered_key) < byte_size(private_value)

    malformed = ~s({"#{private_value}": })

    assert {:error, %Error{code: :invalid_json, details: %{reason: reason}}} =
             JSON.decode(malformed)

    refute reason =~ private_value
    assert byte_size(reason) < byte_size(private_value)

    for aggregate <- aggregate_cases() do
      rejected = %{"credential-sentinel" => private_value}

      assert {:error, errors} =
               aggregate.from_map.(Map.put(aggregate.document, "title", rejected), [])

      schema_errors = Enum.filter(errors, &(&1.code == :schema_violation))
      assert schema_errors != []

      Enum.each(schema_errors, fn error ->
        refute inspect(error.details) =~ private_value
      end)
    end
  end

  test "lexical checks refuse deeply nested and oversized strings before decoding" do
    hostile_depth = String.duplicate("[", 100_000)
    hostile_string = "\"" <> String.duplicate("x", 100_000)

    assert {:error, %Error{code: :depth_limit_exceeded, phase: :parse}} =
             JSON.decode(hostile_depth, max_depth: 8)

    assert {:error, %Error{code: :string_limit_exceeded, phase: :parse}} =
             JSON.decode(hostile_string, max_string_bytes: 16)
  end

  defp aggregate_cases do
    [
      %{
        document: valid_td_map(),
        from_map: &ThingDescription.from_map/2,
        parse: &ThingDescription.parse/2,
        parse_bang: &ThingDescription.parse!/2,
        to_map: &ThingDescription.to_map/1,
        validate: &ThingDescription.validate/2,
        put_id: &ThingDescription.put_id/3,
        encode: &ThingDescription.encode/2
      },
      %{
        document: valid_tm_map(),
        from_map: &ThingModel.from_map/2,
        parse: &ThingModel.parse/2,
        parse_bang: &ThingModel.parse!/2,
        to_map: &ThingModel.to_map/1,
        validate: &ThingModel.validate/2,
        put_id: &ThingModel.put_id/3,
        encode: &ThingModel.encode/2
      }
    ]
  end

  defp wrapper_cases do
    [
      wrapper_case(
        DataSchema,
        with_extension(%{"type" => "number"}),
        &DataSchema.new/2,
        &DataSchema.to_map/1
      ),
      wrapper_case(Form, with_extension(%{"href" => "relative"}), &Form.new/2, &Form.to_map/1),
      wrapper_case(
        PropertyAffordance,
        with_extension(%{"forms" => [%{"href" => "relative"}]}),
        &PropertyAffordance.new/2,
        &PropertyAffordance.to_map/1
      ),
      wrapper_case(
        ActionAffordance,
        with_extension(%{"forms" => [%{"href" => "relative"}]}),
        &ActionAffordance.new/2,
        &ActionAffordance.to_map/1
      ),
      wrapper_case(
        EventAffordance,
        with_extension(%{"forms" => [%{"href" => "relative"}]}),
        &EventAffordance.new/2,
        &EventAffordance.to_map/1
      ),
      wrapper_case(
        SecurityScheme,
        with_extension(%{"scheme" => "nosec"}),
        &SecurityScheme.new/2,
        &SecurityScheme.to_map/1
      )
    ]
  end

  defp wrapper_case(module, document, new, to_map) do
    %{module: module, document: document, new: new, to_map: to_map}
  end

  defp valid_td_map do
    with_extension(%{
      "@context" => Wotex.td_context_1_1(),
      "title" => "Unicode Thing",
      "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
      "security" => ["nosec_sc"]
    })
  end

  defp valid_tm_map do
    with_extension(%{
      "@context" => Wotex.td_context_1_1(),
      "@type" => "tm:ThingModel",
      "title" => "Unicode model"
    })
  end

  defp with_extension(document), do: Map.put(document, @extension_key, @extension_value)

  defp invalid_extension_value(document) do
    Map.put(document, "x/example~", %{"value/key~" => <<255>>})
  end

  defp invalid_extension_key(document) do
    Map.put(document, "x/example~", %{<<255>> => true})
  end

  defp threshold_options(nodes, bytes, depth) do
    [max_nodes: nodes, max_bytes: bytes, max_depth: depth]
  end

  defp metrics(value), do: metrics(value, 0)

  defp metrics(value, depth) when is_map(value) do
    Enum.reduce(value, {1, 0, depth}, fn {key, child}, {nodes, bytes, max_depth} ->
      {child_nodes, child_bytes, child_depth} = metrics(child, depth + 1)
      {nodes + child_nodes, bytes + byte_size(key) + child_bytes, max(max_depth, child_depth)}
    end)
  end

  defp metrics(values, depth) when is_list(values) do
    Enum.reduce(values, {1, 0, depth}, fn child, {nodes, bytes, max_depth} ->
      {child_nodes, child_bytes, child_depth} = metrics(child, depth + 1)
      {nodes + child_nodes, bytes + child_bytes, max(max_depth, child_depth)}
    end)
  end

  defp metrics(value, depth) when is_binary(value), do: {1, byte_size(value), depth}
  defp metrics(_, depth), do: {1, 0, depth}

  defp assert_invalid_options(result) do
    assert {:error, %Error{code: :invalid_options, phase: :value, path: "/"}} = result
  end
end
