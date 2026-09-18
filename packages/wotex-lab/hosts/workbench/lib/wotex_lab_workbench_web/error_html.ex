defmodule WotexLabWorkbenchWeb.ErrorHTML do
  @moduledoc """
  Renders a standard HTTP status phrase for a Phoenix error template.

  Template status determines the phrase through Phoenix's controller helper.
  Request assigns are ignored, so exception details and submitted values do
  not enter the response through this renderer. Error classification and
  logging remain with the endpoint and the code that raised the response.
  """

  use WotexLabWorkbenchWeb, :html

  @doc "Renders the status phrase for any error template."
  @spec render(String.t(), map()) :: String.t()
  def render(template, _), do: Phoenix.Controller.status_message_from_template(template)
end
