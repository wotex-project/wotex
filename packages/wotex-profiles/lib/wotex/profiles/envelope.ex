defmodule Wotex.Profiles.Envelope do
  @moduledoc false

  alias Wotex.Profiles.{Error, Grammar, Parser}

  @options [
    max_bytes: 2_097_152,
    max_depth: 32,
    max_nodes: 50_000,
    max_collection_size: 4096,
    max_string_bytes: 16_384
  ]

  @doc false
  @spec admit(term()) :: {:ok, term()} | {:error, Error.t()}
  def admit(data) do
    with :ok <- Wotex.JSON.validate(data, @options),
         :ok <- Parser.native_numbers(data),
         {:ok, bytes} <- Wotex.JSON.encode(data, @options),
         true <- byte_size(bytes) <= 2_097_152,
         :ok <- Parser.guard_numbers(bytes, 128),
         :ok <- nul(data) do
      {:ok, data}
    else
      false -> Error.refusal(:input_limit)
      {:error, %Wotex.Error{code: code}} -> Grammar.core_refusal(code)
      error -> error
    end
  end

  @doc false
  @spec decode(term()) :: {:ok, term()} | {:error, Error.t()}
  def decode(bytes) when is_binary(bytes) and byte_size(bytes) <= 2_097_152 do
    with {:ok, data} <- Parser.decode_envelope(bytes, @options), do: admit(data)
  end

  def decode(bytes) when is_binary(bytes), do: Error.refusal(:input_limit)
  def decode(_), do: Error.refusal(:invalid_input)

  @doc false
  @spec encode(term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(data) do
    with {:ok, data} <- admit(data) do
      {:ok, _} = success = Wotex.JSON.encode(data, @options)
      success
    end
  end

  defp nul(value) when is_binary(value) do
    if String.contains?(value, <<0>>), do: Error.refusal(:invalid_input), else: :ok
  end

  defp nul(value) when is_list(value), do: Grammar.each(value, &nul/1)

  defp nul(value) when is_map(value),
    do:
      Grammar.each(Map.to_list(value), fn {key, child} ->
        with :ok <- nul(key), do: nul(child)
      end)

  defp nul(_), do: :ok
end
