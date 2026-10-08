defmodule Wotex.Runtime.TestSupport.CodecExecutor do
  @moduledoc false

  @behaviour Wotex.Runtime.Codec.Executor
  @impl Wotex.Runtime.Codec.Executor
  @spec decode(binary(), map(), Wotex.Runtime.Codec.Call.t(), term()) :: term()
  def decode(input, metadata, call, callback), do: callback.(input, metadata, call)
end
