defmodule Wotex.Matter.Check.P03Advisories do
  @moduledoc false

  @endpoint "https://api.osv.dev/v1/querybatch"
  @sources [
    {"connectedhomeip", "GIT", "https://github.com/project-chip/connectedhomeip",
     "250a9e6c50ee2068107f3c4808b680f5f2925415"},
    {"pigweed", "GIT", "https://pigweed.googlesource.com/pigweed/pigweed",
     "c9687b52fa704606d19952255c78142fdb2a131a"},
    {"BoringSSL", "GIT", "https://boringssl.googlesource.com/boringssl",
     "9cac8a6b38c1cbd45c77aee108411d588da006fe"},
    {"nlohmann/json", "GIT", "https://github.com/nlohmann/json",
     "9cca280a4d0ccf0c08f47a99aa71d1b0e52f8d03"},
    {"nlassert", "GIT", "https://github.com/nestlabs/nlassert",
     "c5892c5ae43830f939ed660ff8ac5f1b91d336d3"},
    {"nlio", "GIT", "https://github.com/nestlabs/nlio", "0e725502c2b17bb0a0c22ddd4bcaee9090c8fb5c"},
    {"uriparser", "GIT", "https://github.com/uriparser/uriparser",
     "9b2bed92f5deecf740819f9bf27724bee2fe9c12"},
    {"click", "PyPI", "click", "8.3.3"},
    {"coloredlogs", "PyPI", "coloredlogs", "15.0.1"},
    {"humanfriendly", "PyPI", "humanfriendly", "10.0"},
    {"lark", "PyPI", "lark", "1.1.5"},
    {"Jinja2", "PyPI", "Jinja2", "3.1.6"},
    {"MarkupSafe", "PyPI", "MarkupSafe", "2.1.2"},
    {"lxml", "PyPI", "lxml", "6.1.0"},
    {"python-path", "PyPI", "python-path", "0.1.3"}
  ]

  @spec main() :: :ok
  def main do
    request = %{
      "queries" =>
        Enum.map(@sources, fn
          {_label, "GIT", _repository, revision} ->
            %{"commit" => revision}

          {_label, ecosystem, package, version} ->
            %{"package" => %{"ecosystem" => ecosystem, "name" => package}, "version" => version}
        end)
    }

    {response, status} =
      System.cmd(
        "curl",
        [
          "-fsS",
          "--connect-timeout",
          "10",
          "--max-time",
          "60",
          "--max-filesize",
          "8388608",
          "-H",
          "Content-Type: application/json",
          "--data-binary",
          Jason.encode!(request),
          @endpoint
        ],
        stderr_to_stdout: true
      )

    with 0 <- status,
         {:ok, %{"results" => results}} <- Jason.decode(response),
         true <- length(results) == length(@sources),
         true <- Enum.all?(results, &(&1 == %{} or &1 == %{"vulns" => []})) do
      Enum.each(@sources, fn {label, ecosystem, _package, version} ->
        IO.puts("OSV #{ecosystem} query passed: #{label} #{version}")
      end)

      :ok
    else
      _ ->
        IO.puts(:stderr, "OSV advisory query failed or returned an advisory")
        System.halt(1)
    end
  end
end

Wotex.Matter.Check.P03Advisories.main()
