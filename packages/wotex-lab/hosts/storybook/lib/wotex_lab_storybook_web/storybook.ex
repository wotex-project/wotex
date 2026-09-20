defmodule WotexLabStorybookWeb.Storybook do
  @moduledoc false

  use PhoenixStorybook,
    otp_app: :wotex_lab_storybook,
    content_path: Path.expand("../../storybook", __DIR__),
    title: "Wotex design qualification",
    css_path: "/contract-assets/design-system.css",
    js_path: "/contract-assets/storybook-loader.js",
    sandbox_class: "wotex-lab",
    themes: [
      system: [name: "System"],
      light: [name: "Light"],
      dark: [name: "Dark"],
      contrast: [name: "High contrast"]
    ],
    themes_strategies: [data_attribute: "pa-theme", assign: :theme]
end
