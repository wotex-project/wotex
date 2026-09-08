defmodule WotexLabWorkbench.ChartAssets do
  @moduledoc """
  The pinned, vendored Vega assets.

  `bin/provision_chart_assets.exs` renews these exact npm tarballs, refuses any
  digest other than the recorded one and unpacks the minified builds and
  licenses into `priv/static/vendor/`. They ship with the host; the application
  never downloads them. If a downstream distribution strips them, charts
  still render as server-side SVG with a table alternative and the hook does
  nothing.
  """

  @assets [
    %{
      package: "vega",
      version: "6.4.0",
      sha256: "3521fb6ff68a94a40323954f0ba4484ba4014b157bfd37f89a3b063082320c42",
      file: "vega.min.js",
      license_file: "vega.LICENSE",
      license: "BSD-3-Clause"
    },
    %{
      package: "vega-lite",
      version: "6.4.3",
      sha256: "24260f85e6f5bfe1069505f7c5c2b9863181ac413ef1030746f0a80c93991ce5",
      file: "vega-lite.min.js",
      license_file: "vega-lite.LICENSE",
      license: "BSD-3-Clause"
    },
    %{
      package: "vega-embed",
      version: "7.2.0",
      sha256: "a1d5040a75a894cf8210fa058446474722fa43c6b701fc53f4bbb150fbdd8d68",
      file: "vega-embed.min.js",
      license_file: "vega-embed.LICENSE",
      license: "BSD-3-Clause"
    }
  ]

  @doc "The pinned cohort: package, version, tarball SHA-256, build and license files."
  @spec assets() :: [map()]
  def assets, do: @assets

  @doc "The static paths the layout includes when every asset is present."
  @spec paths() :: [String.t()]
  def paths, do: Enum.map(@assets, &("/vendor/" <> &1.file))

  @doc "True when every pinned build exists under `priv/static/vendor`."
  @spec available?() :: boolean()
  def available? do
    root = Application.app_dir(:wotex_lab_workbench, "priv/static/vendor")

    Enum.all?(@assets, fn asset ->
      File.regular?(Path.join(root, asset.file)) and
        File.regular?(Path.join(root, asset.license_file))
    end)
  end
end
