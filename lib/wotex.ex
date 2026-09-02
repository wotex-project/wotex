defmodule Wotex do
  @moduledoc """
  Consumer-neutral W3C Web of Things values and Thing Description mechanics.

  The production standards baseline is W3C WoT Thing Description 1.1,
  Recommendation 5 December 2023. Use `Wotex.ThingDescription` as the public
  aggregate boundary.
  """

  @td_context_1_1 "https://www.w3.org/2022/wot/td/v1.1"
  @td_media_type "application/td+json"

  @doc "The exact W3C WoT Thing Description 1.1 context supported in production."
  @spec td_context_1_1() :: String.t()
  def td_context_1_1, do: @td_context_1_1

  @doc "The registered media type used for Thing Description JSON."
  @spec td_media_type() :: String.t()
  def td_media_type, do: @td_media_type
end
