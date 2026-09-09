defmodule Wotex.CoAP.Datagram do
  @moduledoc """
  Defines an explicitly selected, generation-bound datagram owner.

  An adapter receives a validated numeric endpoint, generation reference and
  its own explicit options. It owns acquired resources until `close/1` or owner
  death. It delivers `{:wotex_datagram, generation, {:data, ip, port, bytes}}`,
  `{:wotex_datagram, generation, :closed}` or an error with a library-owned code.
  Callback execution must be bounded; selecting a custom adapter grants that
  implementation responsibility for its own resources and callback failures.
  """

  alias Wotex.CoAP.Error
  @type handle :: %{pid: pid(), generation: reference()}
  @type config :: %{
          host: :inet.ip_address(),
          port: :inet.port_number(),
          generation: reference(),
          options: term()
        }

  @doc "Opens owned resources for the explicit owner within the finite timeout."
  @callback open(config(), pid(), pos_integer()) :: {:ok, handle()} | {:error, Error.t()}
  @doc "Transmits one complete datagram to the configured endpoint."
  @callback send(handle(), binary()) :: :ok | {:error, Error.t()}
  @doc "Arms reception of at most one further datagram."
  @callback set_active_once(handle()) :: :ok | {:error, Error.t()}
  @doc "Releases this generation's resources idempotently."
  @callback close(handle()) :: :ok | {:error, Error.t()}
end
