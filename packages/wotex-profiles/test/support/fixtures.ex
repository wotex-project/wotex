defmodule Wotex.Profiles.Test.Fixtures do
  @moduledoc false

  @vectors Path.expand("../../priv/vectors", __DIR__)

  @spec limits() :: map()
  def limits, do: json("limits")
  @spec json(String.t()) :: map()
  def json(name), do: Jason.decode!(bytes(name))
  @spec bytes(String.t()) :: binary()
  def bytes(name), do: File.read!(Path.join(@vectors, name <> ".json"))
  @spec profile() :: map()
  def profile, do: json("industrial-profile")
  @spec definition() :: map()
  def definition, do: json("industrial-definition")
  @spec unit() :: map()
  def unit, do: definition()["unit"]
  @spec encode(term()) :: binary()
  def encode(value), do: Jason.encode!(value)
end
