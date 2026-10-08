defmodule Wotex.Runtime.TestSupport.CodecDecoder do
  @moduledoc false

  @behaviour Wotex.Runtime.Codec.Decoder
  @impl Wotex.Runtime.Codec.Decoder
  @spec decode(binary(), map(), map()) :: term()
  def decode(input, metadata, configuration) do
    case input do
      "hang" ->
        Process.sleep(:infinity)

      "raise" ->
        raise "decoder-secret-canary"

      "exit" ->
        exit("decoder-secret-canary")

      "throw" ->
        throw("decoder-secret-canary")

      "malformed" ->
        {:ok, %{"foreign" => "decoder-secret-canary"}}

      "bad-return" ->
        :foreign

      "refusal" ->
        {:error, :unsupported_format}

      "unknown-refusal" ->
        {:error, :foreign}

      "slow-refusal" ->
        Process.sleep(30)
        {:error, :invalid_input}

      _ ->
        {:ok,
         %{
           "type" => "text",
           "value" =>
             input <> Map.get(metadata, "suffix", "") <> Map.get(configuration, "suffix", "")
         }}
    end
  end
end
