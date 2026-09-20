defmodule WotexLabWorkbenchWeb.Layouts do
  @moduledoc """
  The root document and the app layout.

  The root layout loads the generated token stylesheet, the host stylesheet,
  the Phoenix and LiveView clients from their packages, and the host script,
  every script carrying the request's CSP nonce. No inline script exists.
  """

  use WotexLabWorkbenchWeb, :html

  import PhoenixAssets.Components, only: [vite_assets: 1]

  attr :conn, :map, required: true
  attr :inner_content, :any, required: true

  @doc "The HTML document."
  @spec root(map()) :: Phoenix.LiveView.Rendered.t()
  def root(assigns) do
    assigns = assign(assigns, :nonce, assigns.conn.assigns[:csp_nonce])

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
        <.vite_assets entry="assets/app.ts" nonce={@nonce} />
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end

  @doc "The isolated root document for public documentation LiveViews."
  @spec documentation_root(map()) :: Phoenix.LiveView.Rendered.t()
  def documentation_root(assigns) do
    assigns = assign(assigns, :nonce, assigns.conn.assigns[:csp_nonce])

    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-doc-theme="system">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <title>Wotex documentation</title>
        <link rel="stylesheet" href="/docs-assets/doc-shell.css" />
        <script nonce={@nonce} src="/js/phoenix/phoenix.min.js">
        </script>
        <script nonce={@nonce} src="/js/live_view/phoenix_live_view.min.js">
        </script>
        <script nonce={@nonce} type="module" src="/docs-assets/doc-shell-browser.js">
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
