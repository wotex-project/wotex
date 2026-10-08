defmodule Wotex.Zigbee.ZCL.Wire do
  @moduledoc false

  import Bitwise

  alias Wotex.Zigbee.Error

  @doc false
  @spec encode(byte(), binary(), byte(), atom(), non_neg_integer() | nil) ::
          {:ok, binary()} | {:error, Error.t()}
  def encode(command, payload, sequence, direction, manufacturer)
      when is_binary(payload) and
             is_integer(command) and command in 0..255 and is_integer(sequence) and
             sequence in 0..255 and
             direction in [:client_to_server, :server_to_client] do
    direction_bit = if direction == :server_to_client, do: 8, else: 0

    header = header(manufacturer, direction_bit, sequence, command)

    if header != nil and byte_size(header) + byte_size(payload) <= 128,
      do: {:ok, <<header::binary, payload::binary>>},
      else: invalid()
  end

  def encode(_, _, _, _, _), do: invalid()

  defp header(nil, direction, sequence, command), do: <<direction, sequence, command>>

  defp header(code, direction, sequence, command) when is_integer(code) and code in 0..0xFFFF,
    do: <<4 ||| direction, code::little-16, sequence, command>>

  defp header(_, _, _, _), do: nil

  @doc false
  @spec parse(binary()) :: {:ok, map(), binary()} | {:error, Error.t()}
  def parse(<<control, rest::binary>> = bytes)
      when byte_size(bytes) <= 128 and (control &&& 0xE3) == 0 do
    direction = if (control &&& 8) == 0, do: :client_to_server, else: :server_to_client

    case {(control &&& 4) != 0, rest} do
      {false, <<sequence, command, payload::binary>>} ->
        parsed(nil, direction, sequence, command, payload)

      {true, <<code::little-16, sequence, command, payload::binary>>} ->
        parsed(code, direction, sequence, command, payload)

      _ ->
        invalid()
    end
  end

  def parse(_), do: invalid()

  defp parsed(manufacturer, direction, sequence, command, payload),
    do:
      {:ok,
       %{manufacturer: manufacturer, direction: direction, sequence: sequence, command: command},
       payload}

  defp invalid, do: {:error, %Error{kind: :invalid_frame, operation: :zcl}}
end
