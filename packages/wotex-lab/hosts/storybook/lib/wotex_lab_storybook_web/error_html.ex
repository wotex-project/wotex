defmodule WotexLabStorybookWeb.ErrorHTML do
  @moduledoc false

  use WotexLabStorybookWeb, :html

  @doc "Renders the deliberately minimal error body for the requested template."
  @spec render(String.t(), map()) :: String.t()
  def render("404.html", _), do: "Not found"
  def render(_, _), do: "Internal server error"
end
