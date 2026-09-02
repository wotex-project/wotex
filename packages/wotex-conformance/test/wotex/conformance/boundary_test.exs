defmodule Wotex.Conformance.BoundaryTest do
  use ExUnit.Case, async: false

  test "the library has no application callback" do
    assert Application.load(:wotex_conformance) in [
             :ok,
             {:error, {:already_loaded, :wotex_conformance}}
           ]

    assert Application.spec(:wotex_conformance, :mod) in [nil, []]
  end

  test "production dependencies contain only the JSON value codec" do
    dependencies = Mix.Project.config()[:deps]

    production =
      Enum.reject(dependencies, fn dependency ->
        options = dependency |> Tuple.to_list() |> List.last()
        is_list(options) and Keyword.has_key?(options, :only)
      end)

    assert Enum.map(production, &elem(&1, 0)) == [:jason]

    refute Enum.any?(dependencies, fn dependency ->
             options = dependency |> Tuple.to_list() |> List.last()

             is_list(options) and
               (Keyword.has_key?(options, :path) or Keyword.has_key?(options, :git))
           end)
  end

  test "loading modules performs no filesystem or process registration" do
    before = Process.registered() |> MapSet.new()

    modules = [
      Wotex.Conformance,
      Wotex.Conformance.Artifact,
      Wotex.Conformance.Canonical,
      Wotex.Conformance.Corpus,
      Wotex.Conformance.Runner,
      Wotex.Conformance.Target.External
    ]

    assert Enum.all?(modules, &Code.ensure_loaded?/1)
    after_loading = Process.registered() |> MapSet.new()
    assert after_loading == before
  end
end
