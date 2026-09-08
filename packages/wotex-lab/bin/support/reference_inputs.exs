defmodule Wotex.Lab.Check.ReferenceInputs do
  @moduledoc false

  alias Wotex.Lab.Evidence.Digest

  # Include executable notebooks and compile-time documentation inputs as well
  # as Elixir/test/native source. Build output, caches, PLTs and retained attempt
  # evidence are deliberately outside this source cohort.
  @patterns ~w(lib/**/* test/**/* config/**/* priv/fixtures/**/* priv/models/**/*
               priv/cookbooks/**/* priv/conformance/* priv/conformance/native/*
               priv/conformance/native/src/*.rs priv/conformance/native/tests/*.rs
               priv/conformance/native/probes/*.rs
               docs/specs/**/* docs/plans/**/* docs/decisions/**/* docs/provenance/**/*
               bin/check_reference_consumer.exs bin/check_source_cohort.exs
               bin/support/reference_inputs.exs bin/support/reference_summary.exs
               bin/support/work_directory.exs .check.exs .formatter.exs mix.exs mix.lock
               README.md LICENSE NOTICE CHANGELOG.md SECURITY.md CONTRIBUTING.md)

  def digest(root), do: Digest.tree(root, @patterns)
end
