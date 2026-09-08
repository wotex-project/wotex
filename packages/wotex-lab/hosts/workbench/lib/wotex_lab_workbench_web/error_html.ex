defmodule WotexLabWorkbenchWeb.ErrorHTML do
  @moduledoc "Plain-text error pages; nothing from the request is echoed."

  use WotexLabWorkbenchWeb, :html

  @doc "Renders the status phrase for any error template."
  @spec render(String.t(), map()) :: String.t()
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
