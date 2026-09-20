defmodule WotexLabStorybookWeb do
  @moduledoc false

  @spec controller() :: Macro.t()
  def controller do
    quote do
      use Phoenix.Controller, formats: [:html]
      import Plug.Conn
    end
  end

  @spec html() :: Macro.t()
  def html do
    quote do
      use Phoenix.Component
      import Phoenix.HTML
    end
  end

  @spec verified_routes() :: Macro.t()
  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: WotexLabStorybookWeb.Endpoint,
        router: WotexLabStorybookWeb.Router,
        statics: []
    end
  end

  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])
end
