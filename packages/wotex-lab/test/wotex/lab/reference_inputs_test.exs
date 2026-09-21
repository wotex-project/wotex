Code.require_file("../../../bin/support/reference_inputs.exs", __DIR__)

defmodule Wotex.Lab.ReferenceInputsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Check.ReferenceInputs

  @inputs ~w(lib/example.ex test/example_test.exs config/config.exs
             priv/cookbooks/example.livemd priv/fixtures/example.json
             priv/models/example.maude priv/conformance/profile.json
             priv/conformance/native/Cargo.lock priv/conformance/native/src/main.rs
             priv/conformance/native/src/bin/reference_runner.rs
             priv/conformance/native/tests/lifecycle.rs priv/conformance/native/probes/probe.rs
             priv/provenance/source-index.json priv/provenance/source-cohort.json
             priv/provenance/WLB.05-evidence.json
             bin/build_artifacts.exs bin/check_distribution.exs
             bin/generate_api_surface.exs bin/generate_compatibility_review.exs
             bin/check_reference_consumer.exs bin/check_source_cohort.exs
             bin/check_workbench_archive.exs
             bin/support/archive_repository.exs bin/support/child_environment.exs
             bin/support/compatibility_review.exs
             bin/support/distribution.exs
             bin/support/reference_inputs.exs bin/support/reference_runner.exs
             bin/support/reference_summary.exs
             bin/support/work_directory.exs .check.exs .formatter.exs mix.exs mix.lock
             README.md LICENSE NOTICE CHANGELOG.md SECURITY.md CONTRIBUTING.md)

  @tag :tmp_dir
  test "changed, removed and added source resources invalidate the reference digest", %{
    tmp_dir: root
  } do
    for relative <- @inputs, do: put_file(root, relative, "initial")
    assert {:ok, original} = ReferenceInputs.digest(root)

    assert Enum.sort(ReferenceInputs.files(root)) ==
             Enum.sort(Enum.map(@inputs, &Path.join(root, &1)))

    for relative <- @inputs do
      put_file(root, relative, "changed")
      refute ReferenceInputs.digest(root) == {:ok, original}, relative
      File.rm!(Path.join(root, relative))
      refute ReferenceInputs.digest(root) == {:ok, original}, relative
      put_file(root, relative, "initial")
      assert ReferenceInputs.digest(root) == {:ok, original}
    end

    put_file(root, "priv/cookbooks/new-example.livemd", "new")
    refute ReferenceInputs.digest(root) == {:ok, original}
  end

  @tag :tmp_dir
  test "generated artifacts and previous attempts do not become source inputs", %{tmp_dir: root} do
    put_file(root, "lib/example.ex", "source")
    assert {:ok, original} = ReferenceInputs.digest(root)

    for relative <- ~w(_build/test/module.beam deps/example/lib/module.ex
                       priv/plts/dialyxir.plt priv/conformance/native/target/release/helper
                       .archive-check.reference-previous/evidence.json
                       docs/specs/catalogue.yaml docs/tasks/local/progress.md) do
      put_file(root, relative, "generated")
    end

    assert ReferenceInputs.digest(root) == {:ok, original}
  end

  defp put_file(root, relative, content) do
    path = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end
end
