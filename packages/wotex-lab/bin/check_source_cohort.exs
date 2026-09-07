# Read-only workspace drift guard. Not an artifact-adoption or security proof.
# Runs with Elixir alone: `elixir bin/check_source_cohort.exs [--print]`.

defmodule Wotex.Lab.Check.SourceCohort do
  @moduledoc false

  @patterns ~w(lib/**/* test/**/* priv/w3c/**/* priv/schemas/**/* priv/vectors/**/*
               docs/specs/**/* specs/**/* docs/plans/**/* docs/decisions/**/*
               mix.exs mix.lock README.md CLAUDE.md)

  def run(argv) do
    root = Path.expand("..", __DIR__)
    index = root |> Path.join("docs/provenance/source-index.json") |> File.read!() |> JSON.decode!()

    entries =
      Enum.map(index["packages"], fn package ->
        directory = package["repository"] |> String.split("/") |> List.last()
        Regex.match?(~r/\Awotex(?:-[a-z]+)*\z/, directory) || abort("unexpected source owner")
        repo = Path.join(Path.dirname(root), directory)
        File.dir?(repo) || abort("missing source owner: #{directory}")

        files =
          @patterns
          |> Enum.flat_map(&Path.wildcard(Path.join(repo, &1)))
          |> Enum.filter(&File.regular?/1)
          |> Enum.uniq()
          |> Enum.sort()

        files != [] || abort("empty source owner: #{directory}")

        digest =
          Enum.reduce(files, :crypto.hash_init(:sha256), fn file, acc ->
            symlink?(file) && abort("symlink in source cohort: #{directory}")
            relative = Path.relative_to(file, repo)
            file_digest = :crypto.hash(:sha256, File.read!(file)) |> Base.encode16(case: :lower)

            acc
            |> :crypto.hash_update(relative)
            |> :crypto.hash_update("\0")
            |> :crypto.hash_update(file_digest)
            |> :crypto.hash_update("\n")
          end)
          |> :crypto.hash_final()
          |> Base.encode16(case: :lower)

        %{"package" => package["package"], "files" => length(files), "sha256" => digest}
      end)

    actual = %{
      "schema_version" => "1.0.0",
      "kind" => "workspace_content_cohort",
      "patterns" => @patterns,
      "packages" => entries
    }

    case argv do
      ["--print"] ->
        IO.puts(pretty(actual))

      [] ->
        expected =
          root |> Path.join("docs/provenance/source-cohort.json") |> File.read!() |> JSON.decode!()

        actual == expected ||
          abort(
            "workspace source drift: review changed specs/code/tests and renew evidence before updating the cohort"
          )

        IO.puts(
          "source cohort: #{length(entries)} owners match recorded content; no readiness promotion"
        )

      _other ->
        abort("usage: elixir bin/check_source_cohort.exs [--print]")
    end
  end

  defp symlink?(path), do: match?({:ok, %File.Stat{type: :symlink}}, File.lstat(path))

  # Hand-laid JSON keeping the committed cohort member order.
  defp pretty(actual) do
    patterns = actual["patterns"] |> Enum.map(&"    #{JSON.encode!(&1)}") |> Enum.join(",\n")

    packages =
      actual["packages"]
      |> Enum.map(fn package ->
        "    {\n      \"package\": #{JSON.encode!(package["package"])},\n" <>
          "      \"files\": #{package["files"]},\n" <>
          "      \"sha256\": #{JSON.encode!(package["sha256"])}\n    }"
      end)
      |> Enum.join(",\n")

    "{\n  \"schema_version\": #{JSON.encode!(actual["schema_version"])},\n" <>
      "  \"kind\": #{JSON.encode!(actual["kind"])},\n" <>
      "  \"patterns\": [\n#{patterns}\n  ],\n" <>
      "  \"packages\": [\n#{packages}\n  ]\n}"
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Lab.Check.SourceCohort.run(System.argv())
