defmodule Wotex.Matter.Bridge.Observation do
  @moduledoc """
  Encodes explicit bridge observations and checks their correlated receipts.

  An observation supplies consumer-approved reachability and optional state for
  one opaque Thing and its current endpoint. Temperature uses Matter's signed
  hundredths of a degree Celsius; `nil` retains unavailable state. All five
  observation fields are required. Encoding performs no capability lookup,
  consumer authorization, process I/O or request completion.

  The version-1 observation frame is bounded to 1024 bytes including LF. Its
  nonzero uint64 ID occupies a separate namespace from requests and clock
  probes; the process owner must allocate non-reused IDs within its explicit
  16-byte generation. Receipts are bounded to 512 bytes. `:applied` records SDK
  endpoint validation and state application; it establishes no physical effect.
  `:refused` preserves the endpoint's previously approved state.
  """

  alias Wotex.Matter.Error

  @keys [:thing, :endpoint, :reachable, :on_off, :temperature]
  @uint64 0xFFFFFFFFFFFFFFFF
  @limits [
    max_bytes: 511,
    max_depth: 1,
    max_nodes: 16,
    max_collection_size: 6,
    max_string_bytes: 32
  ]

  @typedoc "Explicit state for one current Thing/endpoint pair; missing state remains unavailable."
  @type t :: %{
          thing: binary(),
          endpoint: 3..65_534,
          reachable: boolean(),
          on_off: boolean() | nil,
          temperature: -32_767..32_767 | nil
        }

  @doc "Encodes one bounded observation for an explicit generation and non-reused ID."
  @spec encode(term(), term(), term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(generation, id, observation)
      when is_binary(generation) and byte_size(generation) == 16 and is_integer(id) and
             id in 1..@uint64 and is_map(observation) and map_size(observation) == 5 do
    with true <- Enum.sort(Map.keys(observation)) == Enum.sort(@keys),
         %{
           thing: thing,
           endpoint: endpoint,
           reachable: reachable,
           on_off: on_off,
           temperature: temperature
         } <- observation,
         true <- is_binary(thing) and byte_size(thing) in 1..256,
         true <- is_integer(endpoint) and endpoint in 3..65_534,
         true <- is_boolean(reachable) and (is_boolean(on_off) or is_nil(on_off)),
         true <- temperature?(temperature),
         {:ok, bytes} <-
           Jason.encode(%{
             "v" => 1,
             "backend" => "matter-bridge",
             "type" => "observation",
             "generation" => Base.encode16(generation, case: :lower),
             "id" => Integer.to_string(id),
             "thing" => Base.encode16(thing, case: :lower),
             "endpoint" => endpoint,
             "reachable" => reachable,
             "on_off" => on_off,
             "temperature" => temperature
           }),
         true <- byte_size(bytes) < 1024 do
      {:ok, bytes <> "\n"}
    else
      _ -> invalid()
    end
  end

  def encode(_, _, _), do: invalid()

  @doc "Checks the exact observation receipt for the expected generation and observation ID."
  @spec decode_receipt(term(), term(), term()) :: {:ok, :applied | :refused} | {:error, Error.t()}
  def decode_receipt(frame, generation, id)
      when is_binary(frame) and byte_size(frame) in 1..512 and is_binary(generation) and
             byte_size(generation) == 16 and is_integer(id) and id in 1..@uint64 do
    with true <- :binary.last(frame) == 10,
         body = binary_part(frame, 0, byte_size(frame) - 1),
         :nomatch <- :binary.match(body, ["\n", "\r", <<0>>]),
         {:ok, value} <- Wotex.JSON.decode(body, @limits),
         true <- is_map(value) and map_size(value) == 6,
         %{
           "v" => 1,
           "backend" => "matter-bridge",
           "type" => "observation-receipt",
           "generation" => encoded_generation,
           "id" => encoded_id,
           "outcome" => outcome
         } <- value,
         true <- value["v"] === 1 and encoded_generation === Base.encode16(generation, case: :lower),
         true <- encoded_id === Integer.to_string(id),
         {:ok, selected} <- Map.fetch(%{"applied" => :applied, "refused" => :refused}, outcome) do
      {:ok, selected}
    else
      _ -> invalid()
    end
  end

  def decode_receipt(_, _, _), do: invalid()

  defp temperature?(nil), do: true
  defp temperature?(value), do: is_integer(value) and value in -32_767..32_767

  defp invalid, do: {:error, Error.new(:invalid_frame)}
end
