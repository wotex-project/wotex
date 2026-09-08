defmodule Wotex.BLE.BlueZ.Options do
  @moduledoc false

  alias Wotex.BLE.{Error, Peer}

  @doc false
  @spec new(term()) :: {:ok, map()} | {:error, Error.t()}
  def new(options) do
    with true <-
           keyword?(options, [:peer, :connection, :bus_address, :owner, :executable, :timeout]),
         {:ok, peer} <- Peer.new(Keyword.get(options, :peer)),
         mode when mode in [:owned, :borrowed] <- Keyword.get(options, :connection, :borrowed),
         owner when is_pid(owner) <- Keyword.get(options, :owner, self()),
         executable = Keyword.get(options, :executable),
         true <- absolute?(executable),
         timeout = Keyword.get(options, :timeout, 5000),
         true <- is_integer(timeout) and timeout in 1..60_000,
         address = Keyword.get(options, :bus_address),
         true <- bus_address?(address) do
      {:ok,
       %{
         owner: owner,
         executable: executable,
         timeout: timeout,
         parameters: %{
           "peer" => %{
             "adapter" => peer.adapter,
             "address" => peer.address,
             "address_type" => Atom.to_string(peer.address_type)
           },
           "connection" => Atom.to_string(mode),
           "bus_address" => address
         }
       }}
    else
      _ -> {:error, Error.new(:invalid_options)}
    end
  end

  @doc false
  @spec discovery(term()) :: {:ok, map()} | {:error, Error.t()}
  def discovery(options) do
    with true <- keyword?(options, [:cursor, :limit]),
         limit = Keyword.get(options, :limit, 64),
         true <- is_integer(limit) and limit in 1..64,
         cursor = Keyword.get(options, :cursor),
         true <- is_nil(cursor) or (is_binary(cursor) and byte_size(cursor) == 32) do
      {:ok, %{"limit" => limit, "cursor" => cursor}}
    else
      _ -> {:error, Error.new(:invalid_options)}
    end
  end

  defp keyword?(options, allowed) do
    if Keyword.keyword?(options) do
      keys = Keyword.keys(options)
      keys -- allowed == [] and length(keys) == length(Enum.uniq(keys))
    else
      false
    end
  end

  defp absolute?(path),
    do: is_binary(path) and byte_size(path) in 1..4096 and Path.type(path) == :absolute

  defp bus_address?(address) do
    is_binary(address) and byte_size(address) <= 4096 and
      Regex.match?(~r/\Aunix:(?:path|abstract)=[^;\x00-\x20]+\z/u, address)
  end
end
