defmodule Wotex.Modbus.RegisterCodecTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Modbus.{RegisterCodec, RegisterCodecFixture, Value}
  alias Wotex.Runtime.{Codec, Context}
  alias Wotex.Runtime.Codec.Beam
  alias Wotex.Runtime.Implementation.{Error, Plan}

  test "immutable shipped references bind exact documents and pure configuration validation" do
    for {filename, reference} <- [
          {"contract.json", RegisterCodec.contract()},
          {"configuration.schema.json", RegisterCodec.configuration_schema()}
        ] do
      bytes = File.read!(Path.join([__DIR__, "../../../priv/fixtures/register_codec", filename]))
      assert reference["sha256"] == Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
      assert is_map(Jason.decode!(bytes))
      assert bytes == canonical(Jason.decode!(bytes))
    end

    assert :ok =
             RegisterCodec.validate_configuration(
               configuration(),
               RegisterCodec.configuration_schema()
             )

    assert {:error, :invalid_configuration} =
             RegisterCodec.validate_configuration(configuration(), %{})

    for bad <- [
          nil,
          %{__struct__: Plan},
          %{},
          Map.put(configuration(), "extra", "canary"),
          Map.put(configuration(), "registers", 0),
          Map.put(configuration(), "registers", 5),
          Map.put(configuration(), "registers", 1.0),
          Map.put(configuration(), "signed", "true"),
          Map.put(configuration(), "scale", -32_769),
          Map.put(configuration(), "scale", 32_768),
          Map.put(configuration(), "byte_order", "foreign"),
          Map.put(configuration(), "word_order", "foreign")
        ] do
      assert {:error, :invalid_configuration} =
               RegisterCodec.validate_configuration(bad, RegisterCodec.configuration_schema())

      assert {:error, :invalid_input} = RegisterCodec.decode(<<1, 2>>, metadata(), bad)
    end
  end

  test "all four byte/word orders have exact decimal output and no floating conversion" do
    for byte <- ~w(big little), word <- ~w(big little) do
      config =
        configuration(%{
          "registers" => 2,
          "byte_order" => byte,
          "word_order" => word,
          "scale" => -2
        })

      input = reorder(<<0x12, 0x34, 0x56, 0x70>>, byte, word)
      assert {:ok, decimal("1234567", -1)} == RegisterCodec.decode(input, metadata(), config)
    end

    assert RegisterCodec.decode(
             <<0x12, 0x3C>>,
             metadata(),
             configuration(%{"signed" => true, "scale" => -2})
           ) == {:ok, decimal("123", -2)}

    assert RegisterCodec.decode(
             <<0x12, 0x3D>>,
             metadata(),
             configuration(%{"signed" => true, "scale" => -2})
           ) == {:ok, decimal("-123", -2)}

    assert RegisterCodec.decode(<<0, 0>>, metadata(), configuration(%{"scale" => 32_767})) ==
             {:ok, decimal("0", 0)}

    assert RegisterCodec.decode(<<0, 0x0C>>, metadata(), configuration(%{"signed" => true})) ==
             {:ok, decimal("0", 0)}

    assert RegisterCodec.decode(
             :binary.copy(<<0x99>>, 8),
             metadata(),
             configuration(%{"registers" => 4})
           ) == {:ok, decimal("9999999999999999", 0)}

    for scale <- [-32_768, 32_767] do
      assert RegisterCodec.decode(<<0, 1>>, metadata(), configuration(%{"scale" => scale})) ==
               {:ok, decimal("1", scale)}
    end
  end

  test "width, digit, sign, metadata, normalization and negative-zero refusals are deterministic" do
    config = configuration()

    for input <- [
          nil,
          <<>>,
          <<1>>,
          <<1, 2, 3>>,
          :binary.copy(<<0>>, 65_536),
          <<0xA1, 0>>,
          <<0, 0x1F>>
        ] do
      assert {:error, :invalid_input} = RegisterCodec.decode(input, metadata(), config)
    end

    for metadata <- [
          nil,
          %{},
          %{"format" => 1},
          %{"format" => <<255>>},
          %{"format" => "packed-bcd-v1", "extra" => "canary"},
          %{"format" => String.duplicate("x", 257)}
        ] do
      assert {:error, :invalid_input} = RegisterCodec.decode(<<1, 2>>, metadata, config)
    end

    assert {:error, :unsupported_format} =
             RegisterCodec.decode(<<1, 2>>, %{"format" => "packed-bcd-v2"}, config)

    for sign <- [0, 11, 14, 15] do
      assert {:error, :invalid_input} =
               RegisterCodec.decode(
                 <<0x12, 3::4, sign::4>>,
                 metadata(),
                 configuration(%{"signed" => true})
               )
    end

    assert {:error, :unsupported_value} =
             RegisterCodec.decode(<<0, 0x0D>>, metadata(), configuration(%{"signed" => true}))

    assert {:error, :unsupported_value} =
             RegisterCodec.decode(<<0, 0x10>>, metadata(), configuration(%{"scale" => 32_767}))

    assert {:ok, decimal("1", 32_767)} ==
             RegisterCodec.decode(<<0, 0x10>>, metadata(), configuration(%{"scale" => 32_766}))
  end

  test "public Runtime Beam projection is correlated and deterministic across generations" do
    config = configuration(%{"scale" => -2})
    plan = RegisterCodecFixture.plan(config)
    second = RegisterCodecFixture.plan(config, 2)

    for p <- [plan, second] do
      supervisor = start_supervised!({Task.Supervisor, max_children: 1}, id: make_ref())

      executor =
        {Beam,
         %{
           decoder: RegisterCodec,
           contract: RegisterCodec.contract(),
           task_supervisor: supervisor,
           current_inputs: fn -> RegisterCodecFixture.inputs() end,
           now: fn -> System.monotonic_time(:millisecond) end
         }}

      context = Context.new!(request_id: "register-value")
      assert {:ok, result} = Codec.decode(p, <<0x12, 0x30>>, metadata(), context, executor)
      assert result.value == decimal("123", -1)
      assert result.instance_key.generation == p.instance_key.generation
      assert result.contract_sha256 == RegisterCodec.contract()["sha256"]
      assert {:ok, ^result} = Codec.decode(p, <<0x12, 0x30>>, metadata(), context, executor)

      assert {:error, %Error{code: :invalid_input}} =
               Codec.decode(p, <<0xFF, 0xFF>>, metadata(), context, executor)

      assert Task.Supervisor.children(supervisor) == []
    end

    assert {:error, %Error{code: :invalid_configuration}} =
             Plan.new(
               plan.admission,
               Map.put(config, "scale", 32_768),
               plan.instance_key,
               &RegisterCodec.validate_configuration/2
             )
  end

  test "the data-only scalar control uses ordinary ordering without implementation admission" do
    assert {:ok, 0x12345670} = Value.decode([0x5670, 0x1234], :uint32, word_order: :little)

    assert RegisterCodec.decode(
             <<0x56, 0x70, 0x12, 0x34>>,
             metadata(),
             configuration(%{"registers" => 2, "word_order" => "little"})
           ) == {:ok, decimal("1234567", 1)}
  end

  defp configuration(changes \\ %{}),
    do:
      Map.merge(
        %{
          "registers" => 1,
          "byte_order" => "big",
          "word_order" => "big",
          "scale" => 0,
          "signed" => false
        },
        changes
      )

  defp metadata, do: %{"format" => "packed-bcd-v1"}

  # The authored contract/schema documents contain ASCII keys and only safe
  # integers; an independent encoder checks their exact canonical fixture bytes.
  defp canonical(value) when is_map(value) do
    pairs = Enum.map(Enum.sort(value), fn {key, v} -> Jason.encode!(key) <> ":" <> canonical(v) end)
    "{" <> Enum.join(pairs, ",") <> "}"
  end

  defp canonical(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical/1) <> "]"

  defp canonical(value), do: Jason.encode!(value)

  defp decimal(coefficient, exponent),
    do: %{"type" => "decimal", "coefficient" => coefficient, "exponent" => exponent}

  defp reorder(bytes, byte, word) do
    words = for <<a, b <- bytes>>, do: if(byte == "big", do: <<a, b>>, else: <<b, a>>)
    words = if word == "big", do: words, else: Enum.reverse(words)
    IO.iodata_to_binary(words)
  end
end
