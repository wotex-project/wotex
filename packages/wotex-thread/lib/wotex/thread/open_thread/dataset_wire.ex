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
  @spec management(term()) :: {:ok, map()} | {:error, Error.t()}
  def management(%{dataset: dataset} = update) when map_size(update) == 1,
    do: management(%{dataset: dataset, extra_tlvs: []})

  def management(%{dataset: dataset, extra_tlvs: extras} = update) when map_size(update) == 2 do
    with {:ok, bytes} <- Dataset.encode(dataset),
         {:ok, combined} <- append_tlvs(extras, bytes),
         {:ok, merged} <- Dataset.decode(combined),
         {:ok, %{dataset: envelope}} <- parameters(merged, :active) do
      {:ok, %{dataset: envelope}}
    end
  end

  def management(_), do: {:error, Error.new(:invalid_dataset)}

  defp append_tlvs([], bytes), do: {:ok, bytes}

  defp append_tlvs([{type, value} | rest], bytes)
       when is_integer(type) and type in 0..255 and is_binary(value) and
              byte_size(bytes) + byte_size(value) + 2 <= 254,
       do: append_tlvs(rest, <<bytes::binary, type, byte_size(value), value::binary>>)

  defp append_tlvs(_, _), do: {:error, Error.new(:invalid_dataset)}

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
