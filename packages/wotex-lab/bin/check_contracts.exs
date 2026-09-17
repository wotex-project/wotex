# Checks local contracts and the pinned snapshot; performs no network access.
# Runs through Mix so the YAML dependency is available:
# `mix run --no-start bin/check_contracts.exs`.

defmodule Wotex.Lab.Check.Contracts do
  @moduledoc false

  alias Wotex.Lab.Documentation

  def run do
    root = Path.expand("..", __DIR__)
    File.cd!(root)

    docs =
      case Documentation.directory(root) do
        {:ok, docs} -> docs
        :error -> check!(false, "missing documentation tree beside the checkout")
      end

    catalogue = YamlElixir.read_from_file!(Path.join(docs, "specs/catalogue.yaml"))
    local_file!(catalogue["completion_plan"])
    local_file!(catalogue["source_index"])
    source = catalogue["source_index"] |> File.read!() |> JSON.decode!()
    check!(source["kind"] == "source_inspection_snapshot", "source snapshot mislabeled")
    local_file!(catalogue["source_cohort"])
    cohort = catalogue["source_cohort"] |> File.read!() |> JSON.decode!()
    check!(cohort["kind"] == "workspace_content_cohort", "source cohort mislabeled")

    check!(
      Enum.map(cohort["packages"], & &1["package"]) ==
        Enum.map(source["packages"], & &1["package"]),
      "source cohort owner mismatch"
    )

    Enum.each(cohort["packages"], fn package ->
      check!(Regex.match?(~r/\A[0-9a-f]{64}\z/, package["sha256"]), "invalid source content digest")
      check!(is_integer(package["files"]) and package["files"] > 0, "invalid source file count")
    end)

    specs = catalogue["specifications"]
    ids = Enum.map(specs, & &1["id"])
    check!(Enum.uniq(ids) == ids, "duplicate specification ID")

    check!(
      docs
      |> Path.join("specs/WLB.*.md")
      |> Path.wildcard()
      |> Enum.map(&Path.join("docs", Path.relative_to(&1, docs)))
      |> Enum.sort() == Enum.sort(Enum.map(specs, & &1["path"])),
      "uncatalogued spec"
    )

    upstream_ids =
      Enum.flat_map(source["packages"], fn package ->
        check!(Regex.match?(~r/\A[0-9a-f]{40}\z/, package["revision"]), "invalid source revision")

        Enum.each(~w(catalogue_sha256 completion_plan_sha256), fn key ->
          check!(Regex.match?(~r/\A[0-9a-f]{64}\z/, package[key]), "missing provenance digest")
        end)

        Enum.map(package["specifications"], &"#{package["package"]}:#{&1["id"]}")
      end)

    plan = File.read!(resolve!(catalogue["completion_plan"]))
    completion_ids = Regex.scan(~r/\| (WLB-C\d+) \|/, plan) |> Enum.map(&Enum.at(&1, 1))
    check!(Enum.uniq(completion_ids) == completion_ids, "duplicate completion ID")

    modules =
      ["lib/**/*.ex", "hosts/*/lib/**/*.ex"]
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.flat_map(fn file ->
        Regex.scan(~r/^ *defmodule ([\w.]+) do/m, File.read!(file)) |> Enum.map(&Enum.at(&1, 1))
      end)

    Enum.each(specs, fn spec ->
      local_file!(spec["path"])
      content = File.read!(resolve!(spec["path"]))
      check!(String.starts_with?(content, "# #{spec["id"]}:"), "spec heading mismatch")

      check!(
        String.contains?(content, "Specification version: #{spec["version"]}."),
        "spec version mismatch"
      )

      check!(
        spec["implementation_status"] in ~w(implemented partial planned),
        "invalid implementation status"
      )

      check!(spec["evidence_status"] in ~w(missing partial complete), "invalid evidence status")

      check!(
        spec["adoption_status"] in ~w(no_reference reference_available artifact_verified),
        "invalid adoption status"
      )

      Enum.each(
        spec["requires"],
        &check!(&1 in ids or &1 in upstream_ids, "unresolved requirement: #{&1}")
      )

      Enum.each(
        spec["completion_items"],
        &check!(&1 in completion_ids, "unresolved completion item: #{&1}")
      )

      Enum.each(spec["implementation_modules"], &check!(&1 in modules, "missing module: #{&1}"))
      Enum.each(spec["executable_evidence"], &local_file!/1)

      if spec["implementation_status"] == "planned" do
        check!(
          spec["implementation_modules"] == [] and spec["executable_evidence"] == [],
          "planned spec claims implementation"
        )

        check!(
          spec["evidence_status"] == "missing" and spec["adoption_status"] == "no_reference",
          "planned spec claims readiness"
        )
      end

      if spec["evidence_status"] == "complete" or spec["adoption_status"] == "artifact_verified" do
        check!(
          Map.has_key?(spec, "evidence_manifest"),
          "stronger readiness needs an evidence manifest"
        )

        local_file!(spec["evidence_manifest"])
      end
    end)

    graph = Map.new(specs, fn spec -> {spec["id"], Enum.filter(spec["requires"], &(&1 in ids))} end)
    Enum.reduce(ids, MapSet.new(), &visit(&1, [], graph, &2))

    seams = source["seams"]

    check!(
      seams |> Enum.map(& &1["id"]) |> Enum.uniq() |> length() == length(seams),
      "duplicate seam ID"
    )

    Enum.each(seams, fn seam ->
      package = Enum.find(source["packages"], &(&1["package"] == seam["package"]))
      check!(not is_nil(package) and seam["lab_spec"] in ids, "unresolved seam owner")
      expected = "#{package["repository"]}/blob/#{package["revision"]}/#{seam["path"]}"
      check!(seam["source_url"] == expected, "unpinned seam source")

      check!(
        Enum.all?(seam["callbacks"], &Regex.match?(~r/\A\w+[!?]?\/\d+\z/, &1)),
        "invalid callback reference"
      )
    end)

    # Relative links may cross between the package and its documentation
    # tree, so every target is checked against both.
    ["README.md", "CONTRIBUTING.md" | Path.wildcard(Path.join(docs, "**/*.md"))]
    |> Enum.each(fn path ->
      ~r/\]\(([^)]+)\)/
      |> Regex.scan(File.read!(path))
      |> Enum.map(&Enum.at(&1, 1))
      |> Enum.reject(&Regex.match?(~r/\A(?:https?:|mailto:|#)/, &1))
      |> Enum.each(fn target ->
        [file | _fragment] = String.split(target, "#")
        candidate = Path.expand(file, Path.dirname(path))

        check!(
          Enum.any?([root, docs], &String.starts_with?(candidate, &1 <> "/")) and
            File.regular?(candidate),
          "missing/unsafe link target in #{Path.relative_to(path, root)}: #{target}"
        )
      end)
    end)

    Enum.each(Path.wildcard("priv/fixtures/**/manifest.json"), fn path ->
      fixture = path |> File.read!() |> JSON.decode!()
      input = Path.join(Path.dirname(path), fixture["input"])
      local_file!(input)
      digest = :crypto.hash(:sha256, File.read!(input)) |> Base.encode16(case: :lower)
      check!(digest == fixture["input_sha256"], "fixture input digest mismatch")
    end)

    IO.puts(
      "contracts: #{length(specs)} specs, #{length(completion_ids)} work packages, " <>
        "#{length(source["packages"])} source owners, #{length(seams)} seams"
    )
  end

  defp visit(id, stack, graph, visited) do
    check!(id not in stack, "spec dependency cycle at #{id}")

    if MapSet.member?(visited, id) do
      visited
    else
      graph
      |> Map.fetch!(id)
      |> Enum.reduce(visited, &visit(&1, [id | stack], graph, &2))
      |> MapSet.put(id)
    end
  end

  # `docs/` paths resolve inside the documentation tree, every other path
  # inside the package; both stay contained.
  defp local_file!(path) do
    case Documentation.resolve(File.cwd!(), path) do
      {:ok, candidate} -> check!(File.regular?(candidate), "missing/unsafe file: #{path}")
      :error -> check!(false, "missing/unsafe file: #{path}")
    end
  end

  defp resolve!(path) do
    {:ok, candidate} = Documentation.resolve(File.cwd!(), path)
    candidate
  end

  defp check!(true, _message), do: :ok

  defp check!(_false, message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Lab.Check.Contracts.run()
