defmodule Wotex.Lab.Check.ReferenceInputs do
  @moduledoc false

  alias Wotex.Lab.Evidence.Digest

  # Include executable notebooks and provenance records as well as
  # Elixir/test/native source. Documentation lives outside the package and is
  # not a source input; build output, caches, PLTs and retained attempt
  # evidence are deliberately outside this source cohort.
  @patterns ~w(lib/**/* test/**/* config/**/* priv/fixtures/**/* priv/models/**/*
               priv/cookbooks/**/* priv/provenance/**/* priv/conformance/*
               priv/conformance/native/* priv/conformance/native/src/*.rs
               priv/conformance/native/src/bin/*.rs
               priv/conformance/native/tests/*.rs priv/conformance/native/probes/*.rs
               bin/build_artifacts.exs bin/check_distribution.exs
               bin/check_reference_consumer.exs bin/check_source_cohort.exs
               bin/check_workbench_archive.exs
               bin/support/archive_repository.exs bin/support/child_environment.exs
               bin/support/distribution.exs
               bin/support/reference_inputs.exs bin/support/reference_runner.exs
               bin/support/reference_summary.exs
               bin/support/work_directory.exs .check.exs .formatter.exs mix.exs mix.lock
               README.md LICENSE NOTICE CHANGELOG.md SECURITY.md CONTRIBUTING.md)

  @spec digest(Path.t()) :: {:ok, String.t()} | {:error, File.posix()}
  def digest(root), do: Digest.tree(root, @patterns)

  @spec files(Path.t()) :: [Path.t()]
  def files(root) do
    @patterns
    |> Enum.flat_map(&Path.wildcard(Path.join(root, &1), match_dot: true))
    |> Enum.filter(&File.regular?/1)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
