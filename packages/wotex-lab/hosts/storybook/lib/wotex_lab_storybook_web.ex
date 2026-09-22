defmodule WotexLabStorybookWeb do
  @moduledoc false

  @doc "Defines the shared Phoenix controller imports for the Storybook host."
  @spec controller() :: Macro.t()
  def controller do
    quote do
      use Phoenix.Controller, formats: [:html]
      import Plug.Conn
    end
  end

  @doc "Defines the shared Phoenix component imports for the Storybook host."
  @spec html() :: Macro.t()
  def html do
    quote do
      use Phoenix.Component
      import Phoenix.HTML
    end
  end

  @doc "Defines verified routes against the isolated Storybook endpoint."
  @spec verified_routes() :: Macro.t()
  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: WotexLabStorybookWeb.Endpoint,
        router: WotexLabStorybookWeb.Router,
        statics: []
    end
  end

  @doc "Expands one admitted Storybook web layer."
  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])
end
