defmodule Wotex.Matter.Bridge.Control do
  @moduledoc """
  Encodes process controls and checks generation-scoped bridge receipts.

  An explicit native process receives `open` and `close` controls for one
  16-byte generation. Its `ready` receipt must name the selected SDK revision
  and generated bridge model; its `closed` receipt retains that generation.
  All controls are scalar-only JSON objects bounded to 512 bytes including LF.
  A receipt identifies the selected protocol/profile, without authenticating
  a Matter principal, qualifying clocks or establishing an operation's effect.
  These pure functions open no process and read no configuration or clock.
  """

  alias Wotex.Matter.Error

  @revision "250a9e6c50ee2068107f3c4808b680f5f2925415"
  @model "dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671"
  @limits [
    max_bytes: 511,
    max_depth: 1,
    max_nodes: 16,
    max_collection_size: 6,
    max_string_bytes: 64
  ]

  @doc "Encodes an explicit process open or close control."
  @spec encode(term(), term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(type, generation)
      when type in [:open, :close] and is_binary(generation) and byte_size(generation) == 16 do
    {:ok,
     Jason.encode!(%{
       "v" => 1,
       "backend" => "matter-bridge",
       "type" => Atom.to_string(type),
       "generation" => Base.encode16(generation, case: :lower)
     }) <> "\n"}
  end

  def encode(_, _), do: invalid()

  @doc "Checks the exact ready or closed receipt for the expected process generation."
  @spec decode(term(), term(), term()) :: :ok | {:error, Error.t()}
  def decode(frame, type, generation)
      when is_binary(frame) and byte_size(frame) in 1..512 and type in [:ready, :closed] and
             is_binary(generation) and byte_size(generation) == 16 do
    with true <- :binary.last(frame) == 10,
         body = binary_part(frame, 0, byte_size(frame) - 1),
         :nomatch <- :binary.match(body, ["\n", "\r", <<0>>]),
         {:ok, value} <- Wotex.JSON.decode(body, @limits),
         true <- value === expected(type, generation) do
      :ok
    else
      _ -> invalid()
    end
  end

  def decode(_, _, _), do: invalid()

  defp expected(type, generation) do
    frame = %{
      "v" => 1,
      "backend" => "matter-bridge",
      "type" => Atom.to_string(type),
      "generation" => Base.encode16(generation, case: :lower)
    }

    if type == :ready,
      do: Map.merge(frame, %{"sdk_revision" => @revision, "model_sha256" => @model}),
      else: frame
  end

  defp invalid, do: {:error, Error.new(:invalid_frame)}
end
