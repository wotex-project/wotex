defmodule WotexLabStorybookWeb.Router do
  @moduledoc false

  use Phoenix.Router
  import PhoenixStorybook.Router

  pipeline :assets do
    plug :accepts, ["html", "css", "js"]
  end

  scope "/", WotexLabStorybookWeb do
    pipe_through :assets

    get "/contract-assets/storybook-loader.js", AssetController, :loader
    get "/contract-assets/storybook-module.js", AssetController, :javascript
    get "/contract-assets/design-system.css", AssetController, :stylesheet
    get "/assets/*path", AssetController, :asset
  end

  scope "/" do
    storybook_assets()
  end

  scope "/" do
    live_storybook "/storybook",
      backend_module: WotexLabStorybookWeb.Storybook,
      csp_nonce_assign_key: :csp_nonce
  end
end
