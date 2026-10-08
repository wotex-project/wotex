defmodule Wotex.Modbus.RegisterCodec do
  @moduledoc """
  Pure packed-decimal register projection into inert Runtime codec values.

  Select byte order, word order, width, sign convention and decimal scale
  explicitly. This application convention grants no transport or device
  authority and makes no Modbus-standard representation claim.
  """
  @behaviour Wotex.Runtime.Codec.Decoder

  @contract_path Path.expand("../../../priv/fixtures/register_codec/contract.json", __DIR__)
  @schema_path Path.expand(
                 "../../../priv/fixtures/register_codec/configuration.schema.json",
                 __DIR__
               )
  @external_resource @contract_path
  @external_resource @schema_path
  @contract_sha256 :crypto.hash(:sha256, File.read!(@contract_path)) |> Base.encode16(case: :lower)
  @schema_sha256 :crypto.hash(:sha256, File.read!(@schema_path)) |> Base.encode16(case: :lower)
  @fields ~w(registers byte_order word_order scale signed)

  @doc "Returns the exact immutable register-decimal contract reference."
  @spec contract() :: %{required(String.t()) => String.t()}
  def contract,
    do: %{
      "id" => "wotex.modbus.register-decimal",
      "version" => "1.0.0",
      "sha256" => @contract_sha256
    }

  @doc "Returns the exact immutable configuration schema reference."
  @spec configuration_schema() :: %{required(String.t()) => String.t()}
  def configuration_schema,
    do: %{"id" => "wotex.modbus.register-decimal.config", "sha256" => @schema_sha256}

  @doc "Pure schema validator for the explicitly supplied Runtime Plan constructor."
  @spec validate_configuration(term(), term()) :: :ok | {:error, :invalid_configuration}
  def validate_configuration(configuration, schema) do
    if schema == configuration_schema() and configuration?(configuration),
      do: :ok,
      else: {:error, :invalid_configuration}
  end

  @doc "Decodes exact-width packed BCD without floating conversion or effects."
  @impl Wotex.Runtime.Codec.Decoder
  @spec decode(term(), term(), term()) ::
          {:ok, map()} | {:error, Wotex.Runtime.Codec.Decoder.refusal()}
  def decode(input, metadata, configuration) do
    with :ok <- admitted_configuration(configuration),
         :ok <- format(metadata),
         :ok <- input_width(input, configuration["registers"]),
         digits <- nibbles(input, configuration),
         {:ok, digits, sign} <- sign(digits, configuration["signed"]),
         {:ok, coefficient} <- coefficient(digits),
         true <- coefficient != 0 or sign == 1 do
      normalized(coefficient * sign, configuration["scale"])
    else
      {:error, _} = error -> error
      false -> {:error, :unsupported_value}
    end
  end

  defp admitted_configuration(value),
    do: if(configuration?(value), do: :ok, else: {:error, :invalid_input})

  defp input_width(input, width),
    do:
      if(is_binary(input) and byte_size(input) == width * 2,
        do: :ok,
        else: {:error, :invalid_input}
      )

  defp configuration?(value) do
    closed?(value, @fields) and is_integer(value["registers"]) and value["registers"] in 1..4 and
      value["byte_order"] in ~w(big little) and value["word_order"] in ~w(big little) and
      is_integer(value["scale"]) and value["scale"] in -32_768..32_767 and
      is_boolean(value["signed"])
  end

  defp closed?(value, keys),
    do:
      is_map(value) and not is_struct(value) and map_size(value) == length(keys) and
        Enum.all?(keys, &Map.has_key?(value, &1))

  defp format(%{"format" => format} = metadata)
       when map_size(metadata) == 1 and is_binary(format) and byte_size(format) <= 256 do
    cond do
      not String.valid?(format) -> {:error, :invalid_input}
      format == "packed-bcd-v1" -> :ok
      true -> {:error, :unsupported_format}
    end
  end

  defp format(_), do: {:error, :invalid_input}

  defp nibbles(input, configuration) do
    words =
      for <<a, b <- input>>,
        do: if(configuration["byte_order"] == "big", do: <<a, b>>, else: <<b, a>>)

    words = if configuration["word_order"] == "big", do: words, else: Enum.reverse(words)
    for word <- words, <<digit::4 <- word>>, do: digit
  end

  defp sign(digits, false), do: {:ok, digits, 1}

  defp sign(digits, true) do
    {digits, [sign]} = Enum.split(digits, length(digits) - 1)

    case sign do
      12 -> {:ok, digits, 1}
      13 -> {:ok, digits, -1}
      _ -> {:error, :invalid_input}
    end
  end

  defp coefficient(digits) do
    Enum.reduce_while(digits, {:ok, 0}, fn
      digit, {:ok, acc} when digit <= 9 -> {:cont, {:ok, acc * 10 + digit}}
      _, _ -> {:halt, {:error, :invalid_input}}
    end)
  end

  defp normalized(0, _), do: {:ok, %{"type" => "decimal", "coefficient" => "0", "exponent" => 0}}

  defp normalized(value, exponent) when rem(value, 10) == 0,
    do: normalized(div(value, 10), exponent + 1)

  defp normalized(value, exponent) when exponent in -32_768..32_767,
    do:
      {:ok,
       %{"type" => "decimal", "coefficient" => Integer.to_string(value), "exponent" => exponent}}

  defp normalized(_, _), do: {:error, :unsupported_value}
end
