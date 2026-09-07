defmodule Wotex.Lab.Test.CallerBackend do
  @moduledoc false

  # A sentinel backend: selection succeeds, but any numerical use must fail.
  # The example must select its own backend and then restore this caller choice.
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts
end
