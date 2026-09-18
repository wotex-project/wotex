defmodule Wotex.Matter.Check.P02Advisories do
  @moduledoc false

  @endpoint "https://api.osv.dev/v1/querybatch"
  @sources [
    {"connectedhomeip", "https://github.com/project-chip/connectedhomeip",
     "250a9e6c50ee2068107f3c4808b680f5f2925415"},
    {"nlohmann/json", "https://github.com/nlohmann/json",
     "9cca280a4d0ccf0c08f47a99aa71d1b0e52f8d03"},
    {"nestlabs/nlassert", "https://github.com/nestlabs/nlassert",
     "c5892c5ae43830f939ed660ff8ac5f1b91d336d3"},
    {"nestlabs/nlio", "https://github.com/nestlabs/nlio",
     "0e725502c2b17bb0a0c22ddd4bcaee9090c8fb5c"}
  ]

  @spec main() :: :ok
  def main do
    request = %{
      "queries" =>
        Enum.map(@sources, fn {_label, _repository, revision} ->
          %{"commit" => revision}
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
      Enum.each(@sources, fn {label, _repository, revision} ->
        IO.puts("OSV GIT query passed: #{label} #{revision}")
      end)

      :ok
    else
      _ ->
        IO.puts(:stderr, "OSV advisory query failed or returned an advisory")
        System.halt(1)
    end
  end
end

Wotex.Matter.Check.P02Advisories.main()
