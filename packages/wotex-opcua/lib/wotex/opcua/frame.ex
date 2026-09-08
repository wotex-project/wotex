defmodule Wotex.OPCUA.Frame do
  @moduledoc "Incremental bounded UA TCP chunk framing; no security or service success is inferred."
  alias Wotex.OPCUA.Error
  @types ["HEL", "ACK", "ERR", "OPN", "MSG", "CLO"]

  @doc "Decodes one chunk and returns the unconsumed stream tail."
  @spec decode(term(), pos_integer()) :: {:ok, map(), binary()} | :more | {:error, Error.t()}
  def decode(bytes, limit \\ 1_048_576)

  def decode(bytes, limit)
      when is_binary(bytes) and is_integer(limit) and limit >= 8 and byte_size(bytes) < 8, do: :more

  def decode(<<type::binary-size(3), chunk, size::32-little, rest::binary>>, limit)
      when is_integer(limit) and limit >= 8 do
    cond do
      type not in @types or chunk not in [?F, ?C, ?A] ->
        {:error, Error.new(:invalid_header)}

      type in ["HEL", "ACK", "ERR"] and chunk != ?F ->
        {:error, Error.new(:invalid_chunk)}

      size < 8 or size > limit ->
        {:error, Error.new(:message_limit)}

      byte_size(rest) < size - 8 ->
        :more

      true ->
        {:ok, %{type: type, chunk: chunk, body: binary_part(rest, 0, size - 8)},
         binary_part(rest, size - 8, byte_size(rest) - size + 8)}
    end
  end

  def decode(_, _), do: {:error, Error.new(:invalid_frame)}
end
