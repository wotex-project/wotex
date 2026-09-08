defmodule Wotex.Modbus.Mapping do
  @moduledoc "Explicit Wotex profile of the draft Modbus Form vocabulary; extensions are preserved."

  alias Wotex.Form
  alias Wotex.Modbus.{Command, Connection, Error, Value}

  @functions %{
    "readCoil" => :read_coils,
    "readDiscreteInput" => :read_discrete_inputs,
    "readHoldingRegisters" => :read_holding_registers,
    "readInputRegisters" => :read_input_registers,
    "writeSingleCoil" => :write_coil,
    "writeSingleHoldingRegister" => :write_holding_register,
    "writeMultipleCoils" => :write_coils,
    "writeMultipleHoldingRegisters" => :write_holding_registers
  }
  @types %{
    "xsd:unsignedShort" => :uint16,
    "xsd:short" => :int16,
    "xsd:unsignedInt" => :uint32,
    "xsd:int" => :int32,
    "xsd:unsignedLong" => :uint64,
    "xsd:long" => :int64,
    "xsd:float" => :float32,
    "xsd:double" => :float64
  }
  @operations %{
    readproperty: "readproperty",
    writeproperty: "writeproperty",
    invokeaction: "invokeaction"
  }

  @doc "Maps a Form and selected operation; `base:` resolves relative hrefs explicitly."
  @spec command(Form.t() | map(), atom(), term(), keyword()) :: {:ok, map()} | {:error, term()}
  def command(form, operation, input \\ nil, opts \\ [])

  def command(%Form{value: map}, operation, input, opts) when is_map(map) and not is_struct(map) do
    with :ok <- options(opts),
         {:ok, form} <- Form.new(map),
         do: map_form(form, operation, input, opts)
  end

  def command(form, operation, input, opts) when is_map(form) and not is_struct(form) do
    with {:ok, form} <- Form.new(form), do: command(form, operation, input, opts)
  end

  def command(_, _, _, _), do: {:error, Error.new(:invalid_form)}

  @doc "Converts a read payload according to the mapped explicit scalar type."
  @spec decode(map(), term()) :: {:ok, term()} | {:error, Error.t()}
  def decode(%{value_type: nil}, value), do: {:ok, value}
  def decode(_mapping, :written), do: {:ok, :written}

  def decode(%{value_type: type, value_options: options}, registers),
    do: Value.decode(registers, type, options)

  def decode(_, _), do: {:error, Error.new(:invalid_mapping)}

  defp map_form(form, operation, input, opts) do
    context = if operation == :invokeaction, do: :action, else: :property
    map = Form.to_map(form)

    with :ok <- operation(form, operation, context),
         {:ok, endpoint, offset, quantity, unit} <- endpoint(Form.href(form), map, opts),
         {:ok, function} <- function(map, operation, quantity),
         {:ok, kind, orders} <- conversion(map),
         :ok <- scalar_shape(function, quantity, kind),
         {:ok, argument} <- argument(function, input, quantity, kind, orders),
         {:ok, command} <- Command.new(function, offset, argument, unit),
         :ok <- quantity_matches(command, quantity) do
      {:ok,
       %{endpoint: endpoint, command: command, value_type: kind, value_options: orders, form: form}}
    end
  end

  defp options([]), do: :ok
  defp options(base: base) when is_binary(base) or is_nil(base), do: :ok
  defp options(_), do: {:error, Error.new(:invalid_options)}

  defp scalar_shape(_function, _quantity, nil), do: :ok

  defp scalar_shape(function, quantity, kind)
       when function in [
              :read_holding_registers,
              :read_input_registers,
              :write_holding_register,
              :write_holding_registers
            ] do
    {:ok, registers} = Value.encode(if(kind in [:float32, :float64], do: 0.0, else: 0), kind)

    if length(registers) == quantity,
      do: :ok,
      else: {:error, Error.new(:quantity_mismatch)}
  end

  defp scalar_shape(_, _, _), do: {:error, Error.new(:unsupported_conversion)}

  defp operation(form, op, context) do
    if Map.has_key?(@operations, op) and @operations[op] in Form.operations(form, for: context),
      do: :ok,
      else: {:error, Error.new(:unsupported_operation, :op)}
  end

  defp endpoint(href, map, opts) do
    with {:ok, uri} <- URI.new(href),
         {:ok, uri} <- resolve(uri, Keyword.get(opts, :base)),
         :ok <- uri_shape(uri),
         {:ok, _} <- Connection.config(host: uri.host, port: uri.port || 502),
         ["", unit, offset] <- String.split(uri.path || "", "/"),
         {unit, ""} <- Integer.parse(unit),
         {offset, ""} <- Integer.parse(offset),
         {:ok, quantity} <- quantity(uri.query),
         {:ok, offset} <- offset(offset, Map.get(map, "modv:zeroBasedAddressing", false)) do
      {:ok, %{host: uri.host, port: uri.port || 502}, offset, quantity, unit}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_href, :href)}
    end
  end

  defp resolve(%URI{scheme: nil} = uri, base) when is_binary(base) do
    with {:ok, base} <- URI.new(base),
         :ok <- uri_shape(base),
         do: {:ok, URI.merge(base, uri)}
  end

  defp resolve(uri, _), do: {:ok, uri}

  defp uri_shape(%URI{scheme: "modbus+tcp", host: host, userinfo: nil, fragment: nil, port: port})
       when is_binary(host) and host != "" and (is_nil(port) or port in 1..65_535), do: :ok

  defp uri_shape(_), do: {:error, Error.new(:invalid_href, :href)}

  defp quantity(nil), do: {:ok, 1}

  defp quantity(query) do
    case Enum.to_list(URI.query_decoder(query)) do
      [{"quantity", text}] ->
        case Integer.parse(text) do
          {quantity, ""} when quantity in 1..2000 -> {:ok, quantity}
          _ -> {:error, Error.new(:invalid_quantity, :quantity)}
        end

      _ ->
        {:error, Error.new(:invalid_quantity, :quantity)}
    end
  end

  defp offset(offset, true), do: {:ok, offset}
  defp offset(offset, false), do: {:ok, offset - 1}
  defp offset(_, _), do: {:error, Error.new(:invalid_address_base)}

  defp function(%{"modv:entity" => entity}, operation, quantity) do
    case {entity, operation, quantity} do
      {"Coil", :readproperty, _} ->
        {:ok, :read_coils}

      {"DiscreteInput", :readproperty, _} ->
        {:ok, :read_discrete_inputs}

      {"HoldingRegister", :readproperty, _} ->
        {:ok, :read_holding_registers}

      {"InputRegister", :readproperty, _} ->
        {:ok, :read_input_registers}

      {"Coil", op, 1} when op in [:writeproperty, :invokeaction] ->
        {:ok, :write_coil}

      {"Coil", op, _} when op in [:writeproperty, :invokeaction] ->
        {:ok, :write_coils}

      {"HoldingRegister", op, 1} when op in [:writeproperty, :invokeaction] ->
        {:ok, :write_holding_register}

      {"HoldingRegister", op, _} when op in [:writeproperty, :invokeaction] ->
        {:ok, :write_holding_registers}

      _ ->
        {:error, Error.new(:unsupported_operation, :entity)}
    end
  end

  defp function(%{"modv:function" => name}, operation, _quantity) do
    case Map.fetch(@functions, name) do
      {:ok, function} ->
        read? = String.starts_with?(Atom.to_string(function), "read_")

        if read? == (operation == :readproperty),
          do: {:ok, function},
          else: {:error, Error.new(:operation_mismatch)}

      :error ->
        {:error, Error.new(:unsupported_function)}
    end
  end

  defp function(_, _, _), do: {:error, Error.new(:missing_function)}

  defp conversion(map) do
    byte = Map.get(map, "modv:mostSignificantByte", true)
    word = Map.get(map, "modv:mostSignificantWord", true)
    type = Map.get(map, "modv:type")

    if is_boolean(byte) and is_boolean(word) and (is_nil(type) or Map.has_key?(@types, type)),
      do:
        {:ok, @types[type],
         [
           byte_order: if(byte, do: :big, else: :little),
           word_order: if(word, do: :big, else: :little)
         ]},
      else: {:error, Error.new(:unsupported_conversion)}
  end

  defp argument(function, _input, quantity, _kind, _orders)
       when function in [
              :read_coils,
              :read_discrete_inputs,
              :read_holding_registers,
              :read_input_registers
            ],
       do: {:ok, quantity}

  defp argument(_function, input, _quantity, nil, _orders), do: {:ok, input}

  defp argument(function, input, _quantity, kind, orders) do
    with {:ok, registers} <- Value.encode(input, kind, orders) do
      if function == :write_holding_register and length(registers) == 1,
        do: {:ok, hd(registers)},
        else: {:ok, registers}
    end
  end

  defp quantity_matches(%Command{address: %{quantity: quantity}}, quantity), do: :ok
  defp quantity_matches(_, _), do: {:error, Error.new(:quantity_mismatch)}
end
