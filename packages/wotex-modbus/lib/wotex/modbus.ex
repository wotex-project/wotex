defmodule Wotex.Modbus do
  @moduledoc "Modbus TCP client and neutral compatibility surface for the supported function subset."

  import Kernel, except: [send: 2]
  alias Wotex.Modbus.{Address, Command, Connection, Error, Session, Value}

  @doc "Reports implemented capabilities, without a delivery or physical-effect guarantee."
  @spec capabilities() :: %{
          bidirectional: true,
          reliable: true,
          ordered: true,
          multicast: false,
          qos_levels: [:at_most_once, ...],
          max_payload_size: 253,
          connection_oriented: true,
          supports_streaming: false,
          discovery_capable: false,
          transport: [:tcp, ...],
          functions: [1 | 2 | 3 | 4 | 5 | 6 | 15 | 16, ...],
          security: [:none, ...]
        }
  def capabilities do
    %{
      bidirectional: true,
      reliable: true,
      ordered: true,
      multicast: false,
      qos_levels: [:at_most_once],
      max_payload_size: 253,
      connection_oriented: true,
      supports_streaming: false,
      discovery_capable: false,
      transport: [:tcp],
      functions: [1, 2, 3, 4, 5, 6, 15, 16],
      security: [:none]
    }
  end

  @doc "Opens a linked, explicitly owned connection to a numeric IP address."
  @spec connect(keyword()) :: {:ok, Session.t()} | {:error, term()}
  def connect(opts) do
    with {:ok, config} <- Connection.config(opts),
         {:ok, address} <- Address.new(0, 1, Keyword.get(opts, :unit_id, 1)),
         {:ok, pid} <- Connection.start_link(opts) do
      {:ok, %Session{pid: pid, unit_id: address.unit_id, timeout: config.timeout}}
    end
  end

  @doc "Executes a typed command through its owning connection."
  @spec request(Session.t(), Command.t()) :: {:ok, term()} | {:error, Error.t()}
  def request(%Session{} = session, %Command{} = command),
    do: Connection.request(session.pid, command, session.timeout)

  @doc "Dispatches legacy-shaped read and write message maps through validated commands."
  @spec send(Session.t(), map()) :: {:ok, term()} | :ok | {:error, Error.t()}
  def send(%Session{} = session, %{type: operation, address: address} = message) do
    input = Map.get(message, :values, Map.get(message, :value, Map.get(message, :count)))

    with {:ok, command} <- Command.new(operation, address, input, session.unit_id),
         {:ok, value} <- request(session, command) do
      if Command.write?(command), do: :ok, else: {:ok, value}
    end
  end

  def send(_, _), do: {:error, Error.new(:invalid_message)}

  @doc "Closes all resources owned by this session; repeated calls succeed."
  @spec disconnect(Session.t()) :: :ok
  def disconnect(%Session{pid: pid}), do: Connection.close(pid)

  @doc "Reads holding register zero as the compatibility health probe."
  @spec health_check(Session.t()) :: {:ok, :healthy} | {:error, Error.t()}
  def health_check(session) do
    with {:ok, [_]} <- read_holding_registers(session, 0, 1), do: {:ok, :healthy}
  end

  @doc "Modbus has no unsolicited receive operation in this profile."
  @spec receive(term(), term()) :: {:error, Error.t()}
  def receive(_, _), do: {:error, Error.new(:not_supported)}

  @doc "Polling scheduling belongs to the consumer."
  @spec subscribe(term(), term()) :: :not_supported
  def subscribe(_, _), do: :not_supported

  @doc "No native subscription is created by this profile."
  @spec unsubscribe(term(), term()) :: :not_supported
  def unsubscribe(_, _), do: :not_supported

  @doc "Reads an IEEE754 float using explicit big-endian register order."
  @spec read_float(Session.t(), term()) :: {:ok, float()} | {:error, Error.t()}
  def read_float(session, address) do
    with {:ok, registers} <- read_holding_registers(session, address, 2),
         do: Value.decode(registers, :float32)
  end

  @doc "Writes an IEEE754 float as two holding registers, without retry."
  @spec write_float(Session.t(), term(), term()) :: :ok | {:error, Error.t()}
  def write_float(session, address, value) do
    with {:ok, registers} <- Value.encode(value, :float32),
         do: write_holding_registers(session, address, registers)
  end

  @doc "Executes read holding registers with validated address and function limits."
  @spec read_holding_registers(Session.t(), term(), term()) :: {:ok, term()} | {:error, Error.t()}
  def read_holding_registers(session, address, count) do
    with {:ok, command} <- Command.new(:read_holding_registers, address, count, session.unit_id) do
      request(session, command)
    end
  end

  @doc "Executes read input registers with validated address and function limits."
  @spec read_input_registers(Session.t(), term(), term()) :: {:ok, term()} | {:error, Error.t()}
  def read_input_registers(session, address, count) do
    with {:ok, command} <- Command.new(:read_input_registers, address, count, session.unit_id) do
      request(session, command)
    end
  end

  @doc "Executes read coils with validated address and function limits."
  @spec read_coils(Session.t(), term(), term()) :: {:ok, term()} | {:error, Error.t()}
  def read_coils(session, address, count) do
    with {:ok, command} <- Command.new(:read_coils, address, count, session.unit_id) do
      request(session, command)
    end
  end

  @doc "Executes read discrete inputs with validated address and function limits."
  @spec read_discrete_inputs(Session.t(), term(), term()) :: {:ok, term()} | {:error, Error.t()}
  def read_discrete_inputs(session, address, count) do
    with {:ok, command} <- Command.new(:read_discrete_inputs, address, count, session.unit_id) do
      request(session, command)
    end
  end

  @doc "Executes write holding register with validated address and function limits."
  @spec write_holding_register(Session.t(), term(), term()) :: :ok | {:error, Error.t()}
  def write_holding_register(session, address, value) do
    with {:ok, command} <- Command.new(:write_holding_register, address, value, session.unit_id),
         {:ok, _} <- request(session, command) do
      :ok
    end
  end

  @doc "Executes write holding registers with validated address and function limits."
  @spec write_holding_registers(Session.t(), term(), term()) :: :ok | {:error, Error.t()}
  def write_holding_registers(session, address, values) do
    with {:ok, command} <- Command.new(:write_holding_registers, address, values, session.unit_id),
         {:ok, _} <- request(session, command) do
      :ok
    end
  end

  @doc "Executes write coil with validated address and function limits."
  @spec write_coil(Session.t(), term(), term()) :: :ok | {:error, Error.t()}
  def write_coil(session, address, value) do
    with {:ok, command} <- Command.new(:write_coil, address, value, session.unit_id),
         {:ok, _} <- request(session, command) do
      :ok
    end
  end

  @doc "Executes write coils with validated address and function limits."
  @spec write_coils(Session.t(), term(), term()) :: :ok | {:error, Error.t()}
  def write_coils(session, address, values) do
    with {:ok, command} <- Command.new(:write_coils, address, values, session.unit_id),
         {:ok, _} <- request(session, command) do
      :ok
    end
  end
end
