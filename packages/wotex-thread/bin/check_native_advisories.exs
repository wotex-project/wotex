defmodule Wotex.Thread.Check.NativeAdvisories do
  @moduledoc false

  # Live release check: every advisory reported for an exact native source pin must have
  # a checked-in review, and a fixed_in_pin review must name upstream ancestors of the pin.
  @dependencies "priv/openthread/dependencies.json"
  @reviews "docs/provenance/native-advisories.json"
  @osv "https://api.osv.dev/v1/querybatch"
  @nvd "https://services.nvd.nist.gov/rest/json/cves/2.0"
  @github "https://api.github.com/repos"
  @decisions ~w(fixed_in_pin not_applicable unrelated)
  # NVD permits five unauthenticated requests in a rolling 30-second window.
  @nvd_interval 7_000

  @spec main() :: :ok
  def main do
    pins = Jason.decode!(File.read!(@dependencies))
    review = Jason.decode!(File.read!(@reviews))
    sources = sources!(review, pins)
    reviews = reviews!(review, sources)

    reported = Enum.uniq(osv(sources) ++ Enum.flat_map(sources, &nvd/1))

    unreviewed = Enum.reject(reported, &Map.has_key?(reviews, &1))
    Enum.each(unreviewed, fn {component, id} -> IO.puts("unreviewed #{component} #{id}") end)

    failed_fixes =
      for {{component, id}, %{"decision" => "fixed_in_pin"} = entry} <- reviews,
          {component, id} in reported,
          commit <- entry["fix_commits"],
          not ancestor?(repository(sources, component), commit, pin(sources, component)),
          do: {component, id, commit}

    Enum.each(failed_fixes, fn {component, id, commit} ->
      IO.puts("fix #{commit} for #{component} #{id} is not an ancestor of the pin")
    end)

    for {component, id} = key <- reported, Map.has_key?(reviews, key) do
      IO.puts("reviewed #{component} #{id}: #{reviews[key]["decision"]}")
    end

    IO.puts("reported #{length(reported)}; unreviewed #{length(unreviewed)}")

    if unreviewed == [] and failed_fixes == [], do: :ok, else: System.halt(1)
  end

  defp sources!(
         %{"format" => "wotex.native-advisories", "version" => 1, "sources" => sources},
         pins
       ) do
    json = pins["json"]["version"]

    for source <- sources do
      %{"component" => component, "repository" => repository, "commit" => commit} = source
      true = commit =~ ~r/\A[0-9a-f]{40}\z/

      case component do
        "json" -> true = source["tag"] == "v" <> json
        _ -> %{"repository" => ^repository, "commit" => ^commit} = pins["sources"][component]
      end

      source
    end
  end

  defp reviews!(%{"reviews" => reviews}, sources) do
    components = Enum.map(sources, & &1["component"])

    Map.new(reviews, fn %{"id" => id, "component" => component, "decision" => decision} = entry ->
      true = component in components and decision in @decisions and is_binary(entry["reason"])
      true = decision != "fixed_in_pin" or match?([_ | _], entry["fix_commits"])
      {{component, id}, entry}
    end)
  end

  defp osv(sources) do
    body = Jason.encode!(%{"queries" => Enum.map(sources, &%{"commit" => &1["commit"]})})
    %{"results" => results} = request!(:post, @osv, body)
    true = length(results) == length(sources)

    for {source, result} <- Enum.zip(sources, results),
        advisory <- Map.get(result, "vulns", []),
        do: {source["component"], advisory["id"]}
  end

  defp nvd(source) do
    for query <- source["nvd"], id <- nvd_ids(query), do: {source["component"], id}
  end

  defp nvd_ids(query) do
    Process.sleep(@nvd_interval)

    parameters =
      case query do
        %{"cpe" => cpe} -> %{"virtualMatchString" => cpe}
        %{"keyword" => keyword} -> %{"keywordSearch" => keyword}
      end

    url = @nvd <> "?" <> URI.encode_query(Map.put(parameters, "resultsPerPage", "2000"))
    %{"totalResults" => total, "vulnerabilities" => vulnerabilities} = request!(:get, url, nil)
    true = total == length(vulnerabilities)
    Enum.map(vulnerabilities, & &1["cve"]["id"])
  end

  defp ancestor?(repository, commit, pin) do
    url = "#{@github}/#{repository}/compare/#{commit}...#{pin}"
    %{"status" => status, "behind_by" => behind} = request!(:get, url, nil)
    status in ["ahead", "identical"] and behind == 0
  end

  defp repository(sources, component), do: field(sources, component, "repository")
  defp pin(sources, component), do: field(sources, component, "commit")

  defp field(sources, component, key),
    do: Enum.find_value(sources, &(&1["component"] == component and &1[key]))

  defp request!(method, url, body) do
    arguments =
      ["-fsS", "--proto", "=https", "--connect-timeout", "10", "--max-time", "120"] ++
        ["--max-filesize", "33554432", "-H", "Accept: application/json"] ++
        if(method == :post,
          do: ["-H", "Content-Type: application/json", "--data-binary", body],
          else: []
        ) ++ [url]

    environment =
      Enum.map(System.get_env(), fn {key, value} -> {key, if(key == "PATH", do: value)} end)

    case System.cmd("curl", arguments, stderr_to_stdout: true, env: environment) do
      {response, 0} ->
        digest = Base.encode16(:crypto.hash(:sha256, response), case: :lower)
        IO.puts("response #{digest} #{url}")
        Jason.decode!(response)

      {output, status} ->
        IO.puts(:stderr, "request failed with #{status}: #{url}\n#{output}")
        System.halt(1)
    end
  end
end

Wotex.Thread.Check.NativeAdvisories.main()
