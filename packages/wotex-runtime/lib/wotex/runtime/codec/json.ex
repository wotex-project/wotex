defmodule Wotex.Runtime.Codec.JSON do
  @moduledoc """
  Decodes bounded JSON into exact inert codec values without native floats.

  `decode/1` accepts one complete JSON value with optional JSON whitespace and
  returns `{:ok, value}` in the `Wotex.Runtime.Codec.Value` algebra. Integral
  tokens become signed 64-bit nodes, or unsigned 64-bit nodes when above the
  signed maximum and within the unsigned range. Fractional/exponent tokens stay
  exact decimals: the coefficient has no trailing zeros, the exponent is
  adjusted, and decimal zero becomes coefficient `"0"` with exponent `0`.
  No number passes through a native float.
  Objects retain unique decoded keys ordered by UTF-8 bytes; duplicate keys,
  including equivalent escape spellings, refuse.

      iex> Wotex.Runtime.Codec.JSON.decode("1.2300")
      {:ok, %{"type" => "decimal", "coefficient" => "123", "exponent" => -2}}

  Input is limited to 65,536 bytes and numeric tokens to 128 bytes. The typed
  tree allows depth 8 with the root at depth 1, 1,024 nodes and 256 members per
  collection; text values have at most 4,096 UTF-8 bytes and object keys have
  1 to 128. Decimal coefficients fit signed 64-bit integers and exponents fit
  signed 16-bit integers. The canonical typed representation must also fit
  65,536 bytes, so a JSON input within the input ceiling can still exceed the
  output budget.

  Refusals are payload-free `{:error, reason}` tuples: `:invalid_input` for
  invalid JSON or API input, `:unsupported_value` for unrepresentable values,
  and `:output_limit` for exceeded budgets. `decode/3` implements
  `Wotex.Runtime.Codec.Decoder` with exactly empty metadata and configuration
  maps; other metadata/configuration returns `{:error, :unsupported_format}`.

  The module performs no I/O and starts no worker. Decoding establishes value
  structure, not transport success, source freshness or consumer authority.
  """

  @behaviour Wotex.Runtime.Codec.Decoder
  alias Wotex.Runtime.Codec.{Decoder, Value}

  @signed_min -9_223_372_036_854_775_808
  @signed_max 9_223_372_036_854_775_807
  @unsigned_max 18_446_744_073_709_551_615

  @doc "Decodes one complete JSON value or returns a payload-free contract refusal."
  @spec decode(term()) :: {:ok, Value.t()} | {:error, Decoder.refusal()}
  def decode(input) when is_binary(input) and byte_size(input) in 1..65_536 do
    :ok = numeric_budget(input, :value)
    {value, _, rest} = :json.decode(input, %{nodes: 0, depth: 0, error: nil}, callbacks())
    if whitespace?(rest), do: checked(lift(value)), else: {:error, :invalid_input}
  rescue
    _ -> {:error, :invalid_input}
  catch
    {:json_refusal, code} -> {:error, code}
  end

  def decode(input) when is_binary(input) and byte_size(input) > 65_536,
    do: {:error, :output_limit}

  def decode(_), do: {:error, :invalid_input}

  @doc "Uses the fixed JSON grammar only with exactly empty metadata/configuration."
  @impl Wotex.Runtime.Codec.Decoder
  @spec decode(term(), term(), term()) :: {:ok, Value.t()} | {:error, Decoder.refusal()}
  def decode(input, metadata, configuration)
      when is_map(metadata) and map_size(metadata) == 0 and
             is_map(configuration) and map_size(configuration) == 0,
      do: decode(input)

  def decode(_, _, _), do: {:error, :unsupported_format}

  defp callbacks do
    %{
      integer: &scalar(fn -> integer(&1) end),
      float: &scalar(fn -> decimal(&1) end),
      null: nil,
      array_start: &start(&1, []),
      object_start: &start(&1, %{}),
      array_push: &array_push/2,
      object_push: &object_push/3,
      array_finish: &finish(&1, &2, :list),
      object_finish: &finish(&1, &2, :object)
    }
  end

  defp start(parent, values) do
    frame = %{
      nodes: parent.nodes,
      depth: parent.depth + 1,
      error: parent.error,
      values: values,
      count: 0
    }

    capture(frame, fn ->
      if parent.depth >= 8, do: refuse(:output_limit)
      %{frame | nodes: count(parent.nodes)}
    end)
  end

  defp child(value, frame) do
    if frame.count >= 256 or frame.depth >= 8, do: refuse(:output_limit)
    value = lift(value)
    if match?({:json_refusal, _}, value), do: throw(value)
    nodes = if value["type"] in ["list", "object"], do: frame.nodes, else: count(frame.nodes)
    {value, %{frame | nodes: nodes, count: frame.count + 1}}
  end

  defp count(nodes) when nodes < 1024, do: nodes + 1
  defp count(_), do: refuse(:output_limit)

  defp array_push(value, frame) do
    capture(frame, fn ->
      {value, frame} = child(value, frame)
      %{frame | values: [value | frame.values]}
    end)
  end

  defp object_push(key, value, frame) do
    capture(frame, fn ->
      if byte_size(key) not in 1..128, do: refuse(:unsupported_value)
      if Map.has_key?(frame.values, key), do: refuse(:invalid_input)
      {value, frame} = child(value, frame)
      %{frame | values: Map.put(frame.values, key, value)}
    end)
  end

  defp finish(%{error: code}, parent, _) when code != nil,
    do: {{:json_refusal, code}, %{parent | error: code}}

  defp finish(frame, parent, kind) do
    value =
      case kind do
        :list ->
          %{"type" => "list", "items" => Enum.reverse(frame.values)}

        :object ->
          entries =
            frame.values
            |> Enum.sort_by(&elem(&1, 0))
            |> Enum.map(fn {key, value} -> %{"key" => key, "value" => value} end)

          %{"type" => "object", "entries" => entries}
      end

    {value, %{parent | nodes: frame.nodes}}
  end

  defp integer(token) do
    number = String.to_integer(token)

    cond do
      number in @signed_min..@signed_max ->
        %{"type" => "sint", "value" => Integer.to_string(number)}

      number in 0..@unsigned_max ->
        %{"type" => "uint", "value" => Integer.to_string(number)}

      true ->
        refuse(:unsupported_value)
    end
  end

  defp decimal(token) do
    parts = Regex.run(~r/\A(-?)([0-9]+)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?\z/, token)
    if is_nil(parts), do: refuse(:invalid_input)
    [_, sign, whole | rest] = parts
    fraction = Enum.at(rest, 0, "")
    exponent = Enum.at(rest, 1, "")
    digits = String.trim_leading(whole <> fraction, "0")

    if digits == "" do
      %{"type" => "decimal", "coefficient" => "0", "exponent" => 0}
    else
      coefficient = String.trim_trailing(digits, "0")
      if byte_size(coefficient) > 19, do: refuse(:unsupported_value)
      number = String.to_integer(sign <> coefficient)

      power =
        if(exponent == "", do: 0, else: String.to_integer(exponent)) - byte_size(fraction) +
          byte_size(digits) - byte_size(coefficient)

      if number not in @signed_min..@signed_max or power not in -32_768..32_767,
        do: refuse(:unsupported_value)

      %{"type" => "decimal", "coefficient" => Integer.to_string(number), "exponent" => power}
    end
  end

  # OTP inserts ".0" into exponent-only numeric callback tokens. Check the
  # original byte spans before parsing rather than charging those extra bytes.
  defp numeric_budget(<<>>, _), do: :ok
  defp numeric_budget(<<92, _, rest::binary>>, :string), do: numeric_budget(rest, :string)
  defp numeric_budget(<<34, rest::binary>>, :string), do: numeric_budget(rest, :value)
  defp numeric_budget(<<_, rest::binary>>, :string), do: numeric_budget(rest, :string)
  defp numeric_budget(<<34, rest::binary>>, :value), do: numeric_budget(rest, :string)

  defp numeric_budget(<<byte, _::binary>> = input, :value) when byte == 45 or byte in 48..57 do
    {rest, length} = number_span(input, 0)

    if length > 128, do: refuse(:output_limit)

    numeric_budget(rest, :value)
  end

  defp numeric_budget(<<_, rest::binary>>, :value), do: numeric_budget(rest, :value)

  defp number_span(<<byte, rest::binary>>, length)
       when byte in 48..57 or byte in [43, 45, 46, 69, 101],
       do: number_span(rest, length + 1)

  defp number_span(rest, length), do: {rest, length}
  defp lift(nil), do: %{"type" => "null"}
  defp lift(value) when is_boolean(value), do: %{"type" => "boolean", "value" => value}

  defp lift(value) when is_binary(value) and byte_size(value) <= 4096,
    do: %{"type" => "text", "value" => value}

  defp lift(value) when is_binary(value), do: refuse(:output_limit)
  defp lift(value), do: value

  # OTP catches exceptions around numeric and escaped-string continuations.
  # Carry fixed refusals as data so those catches cannot change their category.
  defp scalar(fun) do
    fun.()
  catch
    {:json_refusal, _} = refusal -> refusal
  end

  defp capture(%{error: code} = frame, _) when code != nil,
    do: %{frame | values: nil}

  defp capture(frame, fun) do
    fun.()
  catch
    {:json_refusal, code} -> %{frame | error: code, values: nil}
  end

  defp checked({:json_refusal, code}), do: {:error, code}

  defp checked(value) do
    case Value.validate(value) do
      {:ok, ^value} -> {:ok, value}
      {:error, %{code: code}} when code in [:unsupported_value, :output_limit] -> {:error, code}
      _ -> {:error, :unsupported_value}
    end
  end

  defp whitespace?(""), do: true
  defp whitespace?(<<byte, rest::binary>>) when byte in [9, 10, 13, 32], do: whitespace?(rest)
  defp whitespace?(_), do: false
  defp refuse(code), do: throw({:json_refusal, code})
end
