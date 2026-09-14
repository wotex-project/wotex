defmodule Wotex.Conformance.BoundaryTest do
  @moduledoc false

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

  test "boundary checker applies an explicit archive root" do
    root =
      Path.join(
        System.tmp_dir!(),
        "wotex-conformance-boundary-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(Path.join(root, "lib"))
    File.mkdir_p!(Path.join(root, "test"))
    File.write!(Path.join(root, "mix.exs"), "defmodule Example.MixProject do\nend\n")
    File.write!(Path.join(root, "lib/value.ex"), "defmodule Example.Value do\nend\n")

    on_exit(fn -> File.rm_rf!(root) end)

    checker = Path.expand("../../../bin/check_boundary.exs", __DIR__)
    command_options = [stderr_to_stdout: true, env: scrubbed_environment()]
    {_, status} = System.cmd("elixir", [checker, root], command_options)
    assert status == 0

    forbidden_line = Enum.join(["use", "GenServer"], " ")

    File.write!(
      Path.join(root, "lib/process.ex"),
      "defmodule Example.Process do\n  #{forbidden_line}\nend\n"
    )

    {output, status} = System.cmd("elixir", [checker, root], command_options)
    assert status == 1
    assert output =~ "lib/process.ex"
    assert output =~ "conformance process, framework, or persistence boundary violation"
  end

  defp scrubbed_environment do
    cleared =
      System.get_env()
      |> Map.delete("PATH")
      |> Map.keys()
      |> Enum.map(&{&1, nil})

    [{"PATH", System.get_env("PATH")} | cleared]
  end
end
