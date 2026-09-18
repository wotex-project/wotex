Code.require_file("bin/evidence.exs")

defmodule Wotex.Directory.EvidenceContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "changed source, dependencies or runtime cannot reuse an archive receipt" do
    snapshot = DirectoryEvidence.snapshot()
    assert DirectoryEvidence.same_inputs!(snapshot, snapshot) == :ok

    for field <- ["source_commit", "inputs", "runtime", "path_dependencies"] do
      assert_raise RuntimeError, ~r/evidence inputs changed/, fn ->
        DirectoryEvidence.same_inputs!(snapshot, Map.put(snapshot, field, nil))
      end
    end
  end

  test "archive result evidence rejects failures, exclusions and incomplete consumer execution" do
    assert DirectoryEvidence.consumer_result!(%{
             "total" => 1,
             "failures" => 0,
             "skipped" => 0,
             "excluded" => 0
           }) == :ok

    for result <- [
          %{"total" => 0, "failures" => 0, "skipped" => 0, "excluded" => 0},
          %{"total" => 1, "failures" => 1, "skipped" => 0, "excluded" => 0},
          %{"total" => 1, "failures" => 0, "skipped" => 1, "excluded" => 0},
          %{"total" => 1, "failures" => 0, "skipped" => 0, "excluded" => 1},
          %{}
        ] do
      assert_raise RuntimeError, ~r/incomplete archive consumer evidence/, fn ->
        DirectoryEvidence.consumer_result!(result)
      end
    end
  end

  test "generated evidence stays external and records explicit check commands" do
    root = DirectoryEvidence.begin(compiler: [command: "mix compile --warnings-as-errors"])

    inputs =
      root
      |> Path.join("inputs.etf")
      |> File.read!()
      |> :erlang.binary_to_term([:safe])

    assert inputs["checks"] == %{
             "compiler" => %{
               "command" => "mix compile --warnings-as-errors",
               "environment" => %{}
             }
           }

    assert Path.type(root) == :absolute
    refute String.starts_with?(root, File.cwd!() <> "/")
    assert File.regular?(Path.join(root, "inputs.etf"))
    refute File.exists?(Path.join(root, "release-evidence.json"))
    assert DirectoryEvidence.external_root!(root) == :ok

    assert_raise RuntimeError, ~r/outside the source tree/, fn ->
      DirectoryEvidence.external_root!(File.cwd!())
    end
  end

  test "modified artifacts cannot be admitted by their earlier checksum" do
    root = DirectoryEvidence.begin([])

    files =
      for name <- ["consumer.mix.lock", "wotex.tar", "wotex_directory-0.1.0.tar"], into: %{} do
        path = Path.join(root, name)
        File.write!(path, "synthetic archive bytes")
        {name, DirectoryEvidence.digest(path)}
      end

    assert DirectoryEvidence.files!(root, files) == :ok
    File.write!(Path.join(root, "wotex.tar"), "changed archive bytes")

    assert_raise RuntimeError, ~r/archive evidence checksum mismatch/, fn ->
      DirectoryEvidence.files!(root, files)
    end

    assert_raise RuntimeError, ~r/file set is incomplete/, fn ->
      DirectoryEvidence.files!(root, Map.delete(files, "consumer.mix.lock"))
    end
  end
end
