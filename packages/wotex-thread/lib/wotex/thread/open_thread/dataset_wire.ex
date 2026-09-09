defmodule Wotex.Thread.OpenThread.DatasetWire do
  @moduledoc false

  alias Wotex.Thread.{Dataset, Error}

  @doc false
  @spec parameters(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def parameters(dataset, kind) do
    with {:ok, selector} <- selector(kind), {:ok, bytes} <- Dataset.encode(dataset) do
      {:ok, Map.put(selector, :dataset, %{type: "bytes", base64: Base.encode64(bytes)})}
    end
  end

  @doc false
  @spec selector(term()) :: {:ok, %{kind: String.t()}} | {:error, Error.t()}
  def selector(kind) when kind in [:active, :pending], do: {:ok, %{kind: Atom.to_string(kind)}}
  def selector(_), do: {:error, Error.new(:invalid_dataset_kind)}

  @doc false
  @spec decode(term()) :: {:ok, Dataset.t()} | {:error, Error.t()}
  def decode(%{"type" => "bytes", "base64" => encoded} = value)
      when map_size(value) == 2 and is_binary(encoded) and byte_size(encoded) <= 340 do
    with {:ok, bytes} <- Base.decode64(encoded),
         true <- byte_size(bytes) <= 254 and Base.encode64(bytes) == encoded,
         {:ok, dataset} <- Dataset.decode(bytes) do
      {:ok, dataset}
    else
      _ -> {:error, Error.new(:invalid_dataset)}
    end
  end

  def decode(_), do: {:error, Error.new(:invalid_dataset)}
end
