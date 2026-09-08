defmodule Wotex.Modbus.ContractFixture do
  @moduledoc false

  alias Wotex.Modbus.{Address, Codec, Command, Error, Value}

  @path Path.expand("../../docs/specs/fixtures/contract-v1.json", __DIR__)
  @ids ~w(FC01 FC02 FC03 FC04 FC05 FC06 FC15 FC16 WRONG-TID WRONG-UNIT
    EXCEPTION-02 EXCEPTION-FF EXCEPTION-EXTRA BYTE-COUNT FRAME-INCOMPLETE FRAME-TAIL
    MBAP-TOO-LARGE RANGE-LAST RANGE-OVERFLOW QUANTITY-126 FORGED-FUNCTION
    ORDER-BIG-BIG ORDER-BIG-LITTLE ORDER-LITTLE-BIG ORDER-LITTLE-LITTLE FLOAT32
    INT16-NEGATIVE FLOAT-NAN WIDTH DUPLICATE-ORDER WRITE-UNCERTAINTY)
  @atoms Map.new(
           [
             :read_coils,
             :read_discrete_inputs,
             :read_holding_registers,
             :read_input_registers,
             :write_coil,
             :write_coils,
             :write_holding_register,
             :write_holding_registers,
             :uint16,
             :int16,
             :uint32,
             :int32,
             :uint64,
             :int64,
             :float32,
             :float64,
             :byte_order,
             :word_order,
             :big,
             :little,
             :offset,
             :quantity,
             :unit_id
           ],
           &{Atom.to_string(&1), &1}
         )

  @doc false
  @spec pure_cases() :: [map()]
  def pure_cases do
    %{"format" => "wotex-protocol-contract", "version" => "1.0.0", "cases" => cases} =
      Jason.decode!(File.read!(@path))

    expected_ids = Enum.sort(Enum.map(@ids, &("WMB-F-" <> &1)))
    ^expected_ids = Enum.sort(Enum.map(cases, &Map.fetch!(&1, "id")))
    Enum.filter(cases, &(&1["tier"] == "pure"))
  end

  @doc false
  @spec digest() :: binary()
  def digest, do: hex(:crypto.hash(:sha256, File.read!(@path)))

  @doc false
  @spec run(map()) :: map()
  def run(%{"operation" => operation, "input" => input}) do
    operation
    |> observe(input)
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp observe("codec.exchange", input) do
    {:ok, command} = command(input["command"])
    {:ok, request} = Codec.encode(command, input["transaction_id"])
    {:ok, frame, <<>>} = Codec.decode(bytes(input["response_hex"]))

    %{
      request_hex: hex(request),
      result: normalize(Codec.response(frame, command, input["transaction_id"]))
    }
  end

  defp observe("codec.decode", input) do
    case Codec.decode(bytes(input["hex"])) do
      {:ok, frame, tail} ->
        %{
          status: :ok,
          frame: %{
            transaction_id: frame.transaction_id,
            unit_id: frame.unit_id,
            pdu_hex: hex(frame.pdu)
          },
          tail_hex: hex(tail)
        }

      other ->
        normalize(other)
    end
  end

  defp observe("command.new", input) do
    case command(input) do
      {:ok, command} ->
        normalize(
          {:ok,
           %{
             function: command.function,
             address: Map.from_struct(command.address),
             values: command.values
           }}
        )

      other ->
        normalize(other)
    end
  end

  defp observe("command.forged_encode", input) do
    address = struct!(Address, Map.new(input["address"], fn {k, v} -> {atom(k), v} end))
    command = %Command{function: input["function"], address: address, values: input["values"]}
    normalize(Codec.encode(command, input["transaction_id"]))
  end

  defp observe("value.encode", input),
    do: normalize(Value.encode(input["value"], atom(input["kind"]), options(input["options"])))

  defp observe("value.decode", input),
    do: normalize(Value.decode(input["registers"], atom(input["kind"]), options(input["options"])))

  defp command(input),
    do: Command.new(atom(input["operation"]), input["offset"], input["input"], input["unit_id"])

  defp normalize({:error, %Error{} = error}),
    do: %{status: :error, error: Map.take(error, [:code, :field, :details, :retryable, :effect])}

  defp normalize({:ok, value}), do: %{status: :ok, value: value}
  defp normalize(:more), do: %{status: :more}
  defp atom(string), do: Map.fetch!(@atoms, string)
  defp options(pairs), do: Enum.map(pairs, fn [key, value] -> {atom(key), atom(value)} end)
  defp bytes(string), do: Base.decode16!(string, case: :lower)
  defp hex(binary), do: Base.encode16(binary, case: :lower)
end
