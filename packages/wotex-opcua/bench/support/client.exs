defmodule Wotex.OPCUA.Bench.Client do
  @moduledoc false

  # An in-process `Wotex.OPCUA.Client` that answers from prepared values, so
  # the benchmarks measure the package's mapping, validation and projection
  # around a client call and not a secure channel. It never starts a process
  # or performs I/O. Options:
  #
  #   * `:read_value` - the native DataValue map returned for a Read;
  #   * `:failure` - an error code returned for every request.

  @behaviour Wotex.OPCUA.Client

  alias Wotex.OPCUA.Error

  @impl Wotex.OPCUA.Client
  def connect(options) do
    {:ok, %{read_value: Keyword.get(options, :read_value), failure: Keyword.get(options, :failure)}}
  end

  @impl Wotex.OPCUA.Client
  def request(%{failure: code}, _, _) when is_atom(code) and not is_nil(code),
    do: {:error, Error.new(code)}

  def request(handle, %{type: :read}, _), do: {:ok, handle.read_value}
  def request(_, %{type: :write}, _), do: {:ok, %{"status" => 0}}

  @impl Wotex.OPCUA.Client
  def disconnect(_), do: :ok
end
