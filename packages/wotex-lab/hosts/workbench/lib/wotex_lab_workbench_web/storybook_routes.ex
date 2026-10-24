defmodule WotexLabWorkbenchWeb.StorybookRoutes do
  @moduledoc false

  @dev_routes Application.compile_env(:wotex_lab_workbench, :dev_routes)

  if @dev_routes do
    @doc false
    defmacro routes do
      quote do
        import PhoenixStorybook.Router

        pipeline :storybook_contract_assets do
          plug(:accepts, ["html", "css", "js"])
          plug(WotexLabWorkbenchWeb.Storybook.SecurityHeaders)
        end

        pipeline :storybook_browser do
          plug(:accepts, ["html"])
          plug(:fetch_session)
          plug(:fetch_live_flash)
          plug(:protect_from_forgery)
          plug(:put_secure_browser_headers)
          plug(WotexLabWorkbenchWeb.Storybook.SecurityHeaders)
        end

        scope "/", WotexLabWorkbenchWeb.Storybook do
          pipe_through(:storybook_contract_assets)

          get("/contract-assets/storybook-loader.js", AssetController, :loader)
          get("/contract-assets/storybook-module.js", AssetController, :javascript)
          get("/contract-assets/design-system.css", AssetController, :stylesheet)

          get(
            "/storybook/assets/css/phoenix_storybook.css",
            AssetController,
            :manager_stylesheet
          )
        end

        scope "/" do
          storybook_assets()
        end

        scope "/" do
          live_storybook("/storybook",
            backend_module: WotexLabWorkbenchWeb.Storybook,
            csp_nonce_assign_key: :csp_nonce,
            pipeline: false
          )
        end
      end
    end
  else
    @doc false
    defmacro routes, do: quote(do: :ok)
  end
end
