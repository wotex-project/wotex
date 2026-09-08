defmodule WotexLabWorkbenchWeb.Layouts do
  @moduledoc """
  The root document and the app layout.

  The root layout loads the generated token stylesheet, the host stylesheet,
  the Phoenix and LiveView clients from their packages, the pinned Vega
  builds when the operator provisioned them, and the host script, every
  script carrying the request's CSP nonce. No inline script exists.
  """

  use WotexLabWorkbenchWeb, :html

  alias WotexLabWorkbench.ChartAssets

  attr :conn, :map, required: true
  attr :inner_content, :any, required: true

  @doc "The HTML document."
  @spec root(map()) :: Phoenix.LiveView.Rendered.t()
  def root(assigns) do
    assigns =
      assigns
      |> assign(:nonce, assigns.conn.assigns[:csp_nonce])
      |> assign(:vendor, if(ChartAssets.available?(), do: ChartAssets.paths(), else: []))

    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <title>WoTEx Lab workbench</title>
        <link rel="stylesheet" href="/css/tokens.css" />
        <link rel="stylesheet" href="/css/host.css" />
        <script nonce={@nonce} src="/js/phoenix/phoenix.min.js">
        </script>
        <script nonce={@nonce} src="/js/live_view/phoenix_live_view.min.js">
        </script>
        <script :for={path <- @vendor} nonce={@nonce} src={path}>
        </script>
        <script nonce={@nonce} src="/js/app.js">
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end

  attr :inner_content, :any, required: true

  @doc "The LiveView layout: the view owns the themed shell."
  @spec app(map()) :: Phoenix.LiveView.Rendered.t()
  def app(assigns) do
    ~H"""
    {@inner_content}
    """
  end
end
