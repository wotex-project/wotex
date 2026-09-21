defmodule WotexLabWorkbench.ProvenanceTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Documentation
  alias WotexLabWorkbench.Provenance

  test "specification digests cover the Lab specifications Wotex.Lab.Documentation locates" do
    expected =
      case Documentation.directory(Mix.Project.deps_paths()[:wotex_lab]) do
        {:ok, directory} ->
          directory
          |> Path.join("specs/WLB.*.md")
          |> Path.wildcard()
          |> Enum.map(&Path.basename/1)

        :error ->
          []
      end

    assert Enum.sort(Map.keys(Provenance.specs())) == Enum.sort(expected)
  end

  test "no host module builds a path into the documentation tree itself" do
    literal = ~r/"(?:\.\.?\/)*(?:[^"\/\n]+\/)*docs(?:\/[^"\n]*)?"/

    for path <- Path.wildcard(Path.expand("../../lib/**/*.ex", __DIR__)) do
      refute Regex.match?(literal, File.read!(path)),
             "#{path} reaches docs/ without Wotex.Lab.Documentation"
    end
  end
end
