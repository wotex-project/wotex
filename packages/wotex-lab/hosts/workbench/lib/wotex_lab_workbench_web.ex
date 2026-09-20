defmodule WotexLabWorkbenchWeb do
  @moduledoc """
  Entry points for the web layer: `use WotexLabWorkbenchWeb, :router`,
  `:controller`, `:live_view`, `:html` or `:component`.

  Every HEEx component of the shell lives in the
  `WotexLabWorkbenchWeb.Components` family and is imported by `:html`
  and `:live_view`; nothing injects caller HTML strings.
  """

  @doc "Static paths the endpoint serves from `priv/static`."
  @spec static_paths() :: [String.t()]
  def static_paths, do: ~w(assets css js favicon.ico robots.txt)

  @doc false
  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])

  @doc false
  @spec router() :: Macro.t()
  def router do
    quote do
      use Phoenix.Router, helpers: false
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  @doc false
  @spec controller() :: Macro.t()
  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]
      import Plug.Conn
      unquote(verified_routes())
    end
  end

  @doc false
  @spec live_view() :: Macro.t()
  def live_view do
    quote do
      use Phoenix.LiveView, layout: {WotexLabWorkbenchWeb.Layouts, :app}
      unquote(html_helpers())
    end
  end

  @doc false
  @spec component() :: Macro.t()
  def component do
    quote do
      use Phoenix.Component
      unquote(html_helpers())
    end
  end

  @doc false
  @spec html() :: Macro.t()
  def html do
    quote do
      use Phoenix.Component
      import Phoenix.Controller, only: [get_csrf_token: 0]
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.HTML
      import WotexLabWorkbenchWeb.Components.Shell
      import WotexLabWorkbenchWeb.Components.ContextHeader
      import WotexLabWorkbenchWeb.Components.Button
      import WotexLabWorkbenchWeb.Components.Field
      import WotexLabWorkbenchWeb.Components.Tabs
      import WotexLabWorkbenchWeb.Components.StatusBadge
      import WotexLabWorkbenchWeb.Components.EmptyState
      import WotexLabWorkbenchWeb.Components.DataTable
      import WotexLabWorkbenchWeb.Components.MetricPanel
      import WotexLabWorkbenchWeb.Components.Chart
      import WotexLabWorkbenchWeb.Components.TensorSummary
      import WotexLabWorkbenchWeb.Components.EvidenceLink
      import WotexLabWorkbenchWeb.Components.PromptComposer
      import WotexLabWorkbenchWeb.Components.AnswerBlock
      import WotexLabWorkbenchWeb.Components.ActionApproval
      import WotexLabWorkbenchWeb.Islands
      unquote(verified_routes())
    end
  end

  defp verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: WotexLabWorkbenchWeb.Endpoint,
        router: WotexLabWorkbenchWeb.Router,
        statics: WotexLabWorkbenchWeb.static_paths()
    end
  end
end
