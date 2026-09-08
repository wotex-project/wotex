# Explicitly provisions the pinned Vega cohort. The application never calls this script.

defmodule WotexLabWorkbench.ProvisionChartAssets do
  @moduledoc false

  Code.require_file("../lib/wotex_lab_workbench/chart_assets.ex", __DIR__)

  def run do
    :inets.start()
    :ssl.start()
    destination = Path.expand("../priv/static/vendor", __DIR__)
    File.mkdir_p!(destination)

    assets = WotexLabWorkbench.ChartAssets.assets()
    Enum.each(assets, &provision(&1, destination))
    IO.puts("chart assets: #{length(assets)} pinned builds and licenses provisioned")
  end

  defp provision(asset, destination) do
    url =
      "https://registry.npmjs.org/#{asset.package}/-/#{asset.package}-#{asset.version}.tgz"

    archive = download(url)
    actual = :crypto.hash(:sha256, archive) |> Base.encode16(case: :lower)

    if actual != asset.sha256 do
      raise "digest mismatch for #{asset.package}@#{asset.version}: #{actual}"
    end

    {:ok, entries} = :erl_tar.extract({:binary, archive}, [:compressed, :memory])
    write_member(entries, "package/build/#{asset.file}", destination, asset.file, asset)
    write_member(entries, "package/LICENSE", destination, asset.license_file, asset)
  end

  defp write_member(entries, member, destination, output, asset) do
    member = String.to_charlist(member)

    case List.keyfind(entries, member, 0) do
      {^member, content} when is_binary(content) ->
        File.write!(Path.join(destination, output), content, [:binary])

      _missing ->
        raise "#{List.to_string(member)} is missing from #{asset.package}@#{asset.version}"
    end
  end

  defp download(url) do
    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    case :httpc.request(:get, {String.to_charlist(url), []}, [ssl: ssl], body_format: :binary) do
      {:ok, {{_http, 200, _reason}, _headers, body}} -> body
      {:ok, {{_http, status, _reason}, _headers, _body}} -> raise "download returned HTTP #{status}"
      {:error, reason} -> raise "download failed: #{inspect(reason)}"
    end
  end
end

WotexLabWorkbench.ProvisionChartAssets.run()
