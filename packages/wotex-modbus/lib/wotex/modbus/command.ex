defmodule Wotex.Modbus.Command do
  @moduledoc """
  Represents a validated request for the supported Modbus function subset.

  `new/4` maps a named read or write operation to function codes 1, 2, 3, 4, 5,
  6, 15, or 16. It constructs a `Wotex.Modbus.Address`, normalizes coil values,
  and enforces function-specific quantity and 16-bit register bounds. Read
  commands carry their quantity in the address; write commands retain explicit
  normalized values.

  `validate/1` rebuilds a command at the wire boundary so a forged struct cannot
  bypass these rules. `write?/1` identifies commands whose transport failure may
  leave an unknown peer effect. The value does not own a socket, deadline,
  retry policy, or authorization decision; those concerns remain with
  `Wotex.Modbus.Connection` and the consumer.
  """

  alias Wotex.Modbus.{Address, Error}

  @reads %{
    read_coils: 1,
    read_discrete_inputs: 2,
    read_holding_registers: 3,
    read_input_registers: 4
  }
  @writes %{write_coil: 5, write_holding_register: 6, write_coils: 15, write_holding_registers: 16}
  @enforce_keys [:function, :address]
  defstruct [:function, :address, values: []]

  @type t :: %__MODULE__{
          function: 1 | 2 | 3 | 4 | 5 | 6 | 15 | 16,
          address: Address.t(),
          values: [boolean() | non_neg_integer()]
        }

  @doc "Builds a read (quantity) or write (value/list) with function-specific limits."
  @spec new(atom(), term(), term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def new(operation, offset, input, unit_id \\ 1) do
    cond do
      Map.has_key?(@reads, operation) -> read(@reads[operation], offset, input, unit_id)
      Map.has_key?(@writes, operation) -> write(@writes[operation], offset, input, unit_id)
      true -> {:error, Error.new(:unsupported_operation, :operation)}
    end
  end

  @doc "Revalidates a command struct at a wire boundary without trusting forged fields."
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(%__MODULE__{address: %Address{} = a, function: f, values: values} = command) do
    operation =
      Enum.find_value(Map.merge(@reads, @writes), fn {op, code} -> if code == f, do: op end)

    input =
      case {f, values} do
        {f, []} when f in [1, 2, 3, 4] -> a.quantity
        {f, [value]} when f in [5, 6] -> value
        {f, values} when f in [15, 16] -> values
        _ -> :invalid
      end

    case new(operation, a.offset, input, a.unit_id) do
      {:ok, ^command} -> :ok
      _ -> {:error, Error.new(:invalid_command)}
    end
  end

  def validate(_), do: {:error, Error.new(:invalid_command)}

  @doc "Whether this command can alter a peer's state."
  @spec write?(t()) :: boolean()
  def write?(%__MODULE__{function: function}), do: function in [5, 6, 15, 16]
  def write?(_), do: false

  defp read(function, offset, quantity, unit) do
    limit = if function in [1, 2], do: 2000, else: 125

    with {:ok, address} <- Address.new(offset, quantity, unit),
         :ok <- limit(quantity, limit) do
      {:ok, %__MODULE__{function: function, address: address}}
    end
  end

  defp write(function, offset, input, unit) do
    values = if function in [5, 6], do: [input], else: input
    maximum = if function == 15, do: 1968, else: 123

    with :ok <- values_shape(values, maximum),
         {:ok, address} <- Address.new(offset, length(values), unit),
         {:ok, values} <- normalize(values, function) do
      {:ok, %__MODULE__{function: function, address: address, values: values}}
    end
  end

  defp limit(quantity, max) when quantity <= max, do: :ok
  defp limit(_, _), do: {:error, Error.new(:invalid_quantity, :quantity)}

  defp values_shape([], _), do: {:error, Error.new(:invalid_quantity, :values)}
  defp values_shape([_ | _] = values, maximum), do: bounded_values(values, maximum)
  defp values_shape(_, _), do: {:error, Error.new(:invalid_value, :values)}

  defp bounded_values([], _), do: :ok
  defp bounded_values([_ | _], 0), do: {:error, Error.new(:invalid_quantity, :values)}
  defp bounded_values([_ | rest], left), do: bounded_values(rest, left - 1)
  defp bounded_values(_, _), do: {:error, Error.new(:invalid_value, :values)}

  defp normalize(values, function) when function in [5, 15] do
    if Enum.all?(values, &(&1 in [true, false, 0, 1])),
      do: {:ok, Enum.map(values, &(&1 in [true, 1]))},
      else: {:error, Error.new(:invalid_value, :values)}
  end

  defp normalize(values, _) do
    if Enum.all?(values, &(is_integer(&1) and &1 in 0..65_535)),
      do: {:ok, values},
      else: {:error, Error.new(:invalid_value, :values)}
  end
end
