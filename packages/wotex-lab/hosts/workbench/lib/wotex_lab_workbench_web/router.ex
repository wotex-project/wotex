defmodule WotexLabWorkbenchWeb.Router do
  @moduledoc """
  Routes: one LiveView with five live actions, the generated token
  stylesheet, session reset and the bounded evidence report.
  """

  use WotexLabWorkbenchWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WotexLabWorkbenchWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug WotexLabWorkbenchWeb.Plugs.ContentSecurityPolicy
    plug WotexLabWorkbenchWeb.Plugs.SessionToken
  end

  pipeline :assets do
    plug :accepts, ["css"]
  end

  pipeline :internal_api do
    plug :accepts, ["json"]
  end

  pipeline :control_api do
    plug :accepts, ["json"]
    plug :put_secure_browser_headers
  end

  scope "/", WotexLabWorkbenchWeb do
    pipe_through :assets
    get "/css/tokens.css", AssetController, :tokens
  end

  scope "/", WotexLabWorkbenchWeb do
    pipe_through :browser

    get "/session/new", SessionController, :new
    get "/evidence/report.json", ReportController, :show
    get "/metrics/dashboard.json", DashboardController, :show

    live_session :workbench, on_mount: [WotexLabWorkbenchWeb.Scope] do
      live "/", WorkbenchLive, :experiments
      live "/runs/:id", WorkbenchLive, :run
      live "/things", WorkbenchLive, :things
      live "/metrics", WorkbenchLive, :metrics
      live "/evidence", WorkbenchLive, :evidence
    end
  end

  scope "/api/internal", WotexLabWorkbenchWeb do
    pipe_through :internal_api
    post "/beamlens/v1/chat/completions", InvestigationCompletionController, :create
  end

  scope "/api/v1", WotexLabWorkbenchWeb do
    pipe_through :control_api
    get "/scenarios", ControlController, :scenarios
    get "/scenarios/:id", ControlController, :scenario
    get "/evidence/:record_id", ControlController, :evidence
    get "/metrics/catalogue", ControlController, :metrics_catalogue
    get "/runs/:run_id", ControlController, :run
    post "/runs", ControlController, :start_run
    post "/runs/:run_id/cancel", ControlController, :cancel_run
    post "/runs/:run_id/approval", ControlController, :approve_decision
  end

  scope "/", WotexLabWorkbenchWeb do
    pipe_through :control_api
    get "/healthz", HealthController, :show
  end
end
