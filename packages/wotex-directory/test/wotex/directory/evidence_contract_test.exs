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
             "total" => 133,
             "failures" => 0,
             "skipped" => 0,
             "excluded" => 0
           }) == :ok

    for result <- [
          %{"total" => 0, "failures" => 0, "skipped" => 0, "excluded" => 0},
          %{"total" => 133, "failures" => 1, "skipped" => 0, "excluded" => 0},
          %{"total" => 133, "failures" => 0, "skipped" => 1, "excluded" => 0},
          %{"total" => 133, "failures" => 0, "skipped" => 0, "excluded" => 1},
          %{}
        ] do
      assert_raise RuntimeError, ~r/incomplete archive consumer evidence/, fn ->
        DirectoryEvidence.consumer_result!(result)
      end
    end
  end

  test "generated evidence is external and the full gate is the sole manifest prerequisite" do
    {configuration, _} = Code.eval_file(".check.exs")
    assert configuration[:retry] == false
    tools = configuration[:tools]
    evidence = tools[:evidence]

    required =
      for {name, options} <- tools, is_list(options), name not in [:evidence, :compiler], do: name

    assert Enum.sort(evidence[:deps]) == Enum.sort(for name <- required, do: {name, [status: 0]})
    assert tools[:ex_unit] == false
    assert tools[:coverage][:command] == "mix coveralls"
    assert tools[:compiler][:command] == "elixir bin/check_compiler.exs"
    root = evidence[:env]["WOTEX_EVIDENCE_ROOT"]
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

  test "every matrix evidence reference resolves to its executable source" do
    matrix = File.read!("docs/specs/claim-compatibility-matrix.md")

    index =
      Regex.scan(~r/\| ([A-Z]) \| `([^`]+)` \|/, matrix)
      |> Map.new(fn [_, key, path] -> {key, path} end)

    references = Regex.scan(~r/`([A-Z]):([^`]+)`/, matrix)
    assert length(references) >= 60

    for [_, key, marker] <- references do
      assert index |> Map.fetch!(key) |> File.read!() |> String.contains?(marker),
             "unresolved evidence reference: #{key}:#{marker}"
    end

    assert "docs/specs/claim-compatibility-matrix.md" in Mix.Project.config()[:package][:files]
  end
end
