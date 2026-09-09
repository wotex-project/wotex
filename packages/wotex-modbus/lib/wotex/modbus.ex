defmodule Wotex.Modbus do
  @moduledoc """
  Executes the supported Modbus TCP function subset through an explicit session.

  `Wotex.Modbus` provides lifecycle, native request, typed convenience, and
  compatibility functions. `connect/1` opens one caller-owned
  `Wotex.Modbus.Connection`; `request/2` sends a validated
  `Wotex.Modbus.Command`; and `disconnect/1` closes the exact connection.
  Helpers cover function codes 1, 2, 3, 4, 5, 6, 15, and 16, including
  explicit floating-point register conversion.

  ## Execution boundary

  Loading this module opens no socket. The consumer supplies the numeric TCP
  endpoint, Unit Identifier, deadline, authorization policy, and supervision.
  Requests on a session are serialized. Writes are never retried silently, and
  failures report when their effect may be unknown. The package does not
  implement RTU or serial transport, Modbus Security, polling, or physical
  certification.
  """

  import Kernel, except: [send: 2]
  alias Wotex.Modbus.{Address, Command, Connection, Error, Session, Value}
  @writes [:write_coil, :write_coils, :write_holding_register, :write_holding_registers]

  @doc "Returns the pure Runtime profile for the implemented native Modbus TCP binding."
  @spec profile() :: Wotex.Runtime.BindingProfile.t()
  def profile do
    {:ok, profile} =
      Wotex.Runtime.BindingProfile.new(
        id: :modbus,
        schemes: ["modbus+tcp"],
        operations: [:readproperty, :writeproperty, :invokeaction],
        media_types: []
      )

    profile
  end

  @doc "Selects an explicitly supported Runtime mode without opening a connection."
  @spec profile(term()) :: {:ok, Wotex.Runtime.BindingProfile.t()} | {:error, Error.t()}
  def profile(:tcp), do: {:ok, profile()}
  def profile(_), do: {:error, Error.new(:unsupported_profile)}

  @doc "Reports implemented capabilities, without a delivery or physical-effect guarantee."
  @spec capabilities() :: %{
          bidirectional: true,
          reliable: true,
          ordered: true,
          multicast: false,
          qos_levels: [:at_most_once, ...],
          max_payload_size: 253,
          max_adu_size: 260,
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
      max_adu_size: 260,
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
  def request(session, command) do
    with :ok <- Session.validate(session),
         :ok <- Command.validate(command),
         do: Connection.request(session.pid, command, session.timeout)
  end

  @doc "Dispatches legacy-shaped read and write message maps through validated commands."
  @spec send(Session.t(), map()) :: {:ok, term()} | :ok | {:error, Error.t()}
  def send(session, %{type: operation, address: address} = message)
      when map_size(message) == 3 do
    with :ok <- Session.validate(session),
         {:ok, input} <- message_input(operation, message),
         {:ok, value} <- execute_helper(session, operation, address, input) do
      if operation in @writes, do: :ok, else: {:ok, value}
    end
  end

  def send(_, _), do: {:error, Error.new(:invalid_message)}

  @doc "Closes all resources owned by this session; repeated calls succeed."
  @spec disconnect(Session.t()) :: :ok | {:error, Error.t()}
  def disconnect(session) do
    with :ok <- Session.validate(session), do: Connection.close(session.pid)
  end

  @doc "Reads holding register zero as the compatibility health probe."
  @spec health_check(Session.t()) :: {:ok, :healthy} | {:error, Error.t()}
  def health_check(session) do
    with {:ok, [_]} <- read_holding_registers(session, 0, 1), do: {:ok, :healthy}
  end

  @doc "Probes health using a validated read command, retaining its unit and address."
  @spec health_check(Session.t(), Command.t()) :: {:ok, :healthy} | {:error, Error.t()}
  def health_check(session, command) do
    with :ok <- Session.validate(session),
         :ok <- Command.validate(command),
         false <- Command.write?(command),
         {:ok, _values} <- request(session, command) do
      {:ok, :healthy}
    else
      true -> {:error, Error.new(:invalid_health_probe)}
      {:error, _} = error -> error
    end
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
  def read_holding_registers(session, address, count),
    do: execute_helper(session, :read_holding_registers, address, count)

  @doc "Executes read input registers with validated address and function limits."
  @spec read_input_registers(Session.t(), term(), term()) :: {:ok, term()} | {:error, Error.t()}
  def read_input_registers(session, address, count),
    do: execute_helper(session, :read_input_registers, address, count)

  @doc "Executes read coils with validated address and function limits."
  @spec read_coils(Session.t(), term(), term()) :: {:ok, term()} | {:error, Error.t()}
  def read_coils(session, address, count),
    do: execute_helper(session, :read_coils, address, count)

  @doc "Executes read discrete inputs with validated address and function limits."
  @spec read_discrete_inputs(Session.t(), term(), term()) :: {:ok, term()} | {:error, Error.t()}
  def read_discrete_inputs(session, address, count),
    do: execute_helper(session, :read_discrete_inputs, address, count)

  @doc "Executes write holding register with validated address and function limits."
  @spec write_holding_register(Session.t(), term(), term()) :: :ok | {:error, Error.t()}
  def write_holding_register(session, address, value),
    do: write_helper(session, :write_holding_register, address, value)

  @doc "Executes write holding registers with validated address and function limits."
  @spec write_holding_registers(Session.t(), term(), term()) :: :ok | {:error, Error.t()}
  def write_holding_registers(session, address, values),
    do: write_helper(session, :write_holding_registers, address, values)

  @doc "Executes write coil with validated address and function limits."
  @spec write_coil(Session.t(), term(), term()) :: :ok | {:error, Error.t()}
  def write_coil(session, address, value),
    do: write_helper(session, :write_coil, address, value)

  @doc "Executes write coils with validated address and function limits."
  @spec write_coils(Session.t(), term(), term()) :: :ok | {:error, Error.t()}
  def write_coils(session, address, values),
    do: write_helper(session, :write_coils, address, values)

  defp execute_helper(session, operation, address, input) do
    with :ok <- Session.validate(session),
         {:ok, command} <- Command.new(operation, address, input, session.unit_id),
         do: request(session, command)
  end

  defp write_helper(session, operation, address, input) do
    with {:ok, _} <- execute_helper(session, operation, address, input), do: :ok
  end

  defp message_input(operation, message) do
    key =
      cond do
        operation in [
          :read_coils,
          :read_discrete_inputs,
          :read_holding_registers,
          :read_input_registers
        ] ->
          :count

        operation in [:write_coil, :write_holding_register] ->
          :value

        operation in [:write_coils, :write_holding_registers] ->
          :values

        true ->
          nil
      end

    case Map.fetch(message, key) do
      {:ok, input} when key in [:count, :value, :values] -> {:ok, input}
      _ -> {:error, Error.new(:invalid_message)}
    end
  end
end
