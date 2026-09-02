defmodule Wotex.Nx do
  @moduledoc """
  Typed W3C Web of Things observation and numerical conversion boundary.

  Conversions are deterministic and inert. This package does not select or run
  a model and never dispatches a Thing Action.
  """

  @quality_codes %{good: 0, uncertain: 1, bad: 2, missing: 3}

  @doc "Returns the stable numerical quality-code mapping."
  @spec quality_codes() :: %{atom() => non_neg_integer()}
  def quality_codes, do: @quality_codes
end
