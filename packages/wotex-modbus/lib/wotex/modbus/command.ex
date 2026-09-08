defmodule Wotex.Modbus.Command do
  @moduledoc "Validated function-specific request, independent of sockets and host policy."

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

  @doc "Whether this command can alter a peer's state."
  @spec write?(t()) :: boolean()
  def write?(%__MODULE__{function: function}), do: function in [5, 6, 15, 16]

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

  defp values_shape(values, max) when is_list(values) do
    if values != [] and length(values) <= max,
      do: :ok,
      else: {:error, Error.new(:invalid_quantity, :values)}
  end

  defp values_shape(_, _), do: {:error, Error.new(:invalid_value, :values)}

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
