defmodule Wotex.Matter.Bench.Client do
  @moduledoc false

  # An in-process `Wotex.Matter.Client` that answers from prepared values, so
  # the benchmarks measure the package's validation and conversion around a
  # client call and not a controller. It never starts a process or performs
  # I/O. Options:
  #
  #   * `:descriptors` - batch-read results keyed by `{endpoint, member}`;
  #   * `:read_value` - the TLV element returned for a concrete read;
  #   * `:failure` - an error code returned for every request.

  @behaviour Wotex.Matter.Client

  alias Wotex.Matter.Error

  @path_keys [:fabric_id, :node_id, :endpoint, :cluster, :member]

  @impl Wotex.Matter.Client
  def connect(options) do
    {:ok,
     %{
       descriptors: Keyword.get(options, :descriptors, %{}),
       read_value: Keyword.get(options, :read_value),
       failure: Keyword.get(options, :failure)
     }}
  end

  @impl Wotex.Matter.Client
  def request(%{failure: code}, _, _) when is_atom(code) and not is_nil(code),
    do: {:error, Error.new(code)}

  def request(handle, %{type: :read_paths, paths: paths}, _),
    do: {:ok, Enum.map(paths, &Map.fetch!(handle.descriptors, {&1.endpoint, &1.member}))}

  def request(handle, %{type: :read} = message, _),
    do: {:ok, %{path: Map.take(message, @path_keys), value: handle.read_value, data_version: 7}}

  def request(_, %{type: :write} = message, _),
    do: {:ok, %{path: Map.take(message, @path_keys), status: 0}}

  def request(_, %{type: :invoke}, _), do: {:ok, %{path: nil, value: nil, status: 0}}

  @impl Wotex.Matter.Client
  def disconnect(_), do: :ok
end
