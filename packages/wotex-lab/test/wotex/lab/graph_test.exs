defmodule Wotex.Lab.GraphTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.{Cookbook, Documentation, Error, Graph}
  alias Wotex.Lab.Graph.{Descriptors, Interfaces, Render}

  @root Path.expand("../../..", __DIR__)
  {:ok, docs} = Documentation.directory(@root)
  @docs docs
  @revision String.duplicate("b", 40)
  @generated_at ~U[2026-09-08 00:00:00Z]
  @hex ~r/\A[0-9a-f]{64}\z/

  setup_all do
    catalogue = YamlElixir.read_from_file!(Path.join(@docs, "specs/catalogue.yaml"))

    index =
      @root |> Path.join("priv/provenance/source-index.json") |> File.read!() |> JSON.decode!()

    {:ok, graph} = generate(catalogue)
    %{catalogue: catalogue, index: index, graph: graph}
  end

  test "the graph is a versioned snapshot joining every input with digests and pinned sources",
       %{graph: graph, catalogue: catalogue, index: index} do
    assert graph["schema_version"] == "1.0.0" and graph["kind"] == "wotex_lab_source_graph"
    assert graph["snapshot"] == true and graph["generated_at"] == "2026-09-08T00:00:00Z"

    assert graph["provenance"] == %{
             "source_index_role" => "historical_baseline",
             "source_cohort_kind" => "workspace_content_cohort"
           }

    assert graph["generator"]["openapi"] == "3.2.0" and graph["generator"]["asyncapi"] == "3.1.0"

    assert length(graph["packages"]) == 9
    assert length(graph["specifications"]) == length(catalogue["specifications"]) + 19
    assert length(graph["cookbooks"]) == 16
    assert length(graph["fixtures"]) == 6
    assert length(graph["seams"]) == length(index["seams"]) + length(Descriptors.seams())
    assert length(graph["adapters"]) == length(Descriptors.adapters())
    assert length(graph["scenarios"]) == 16
    assert length(graph["completions"]) == 14 + 47
    assert length(graph["evidence_overlays"]) == length(catalogue["specifications"]) + 16

    ids = Enum.map(graph["nodes"], & &1["id"])
    assert ids == Enum.uniq(ids)
    known = MapSet.new(ids)

    assert Enum.all?(
             graph["edges"],
             &(MapSet.member?(known, &1["from"]) and MapSet.member?(known, &1["to"]))
           )

    lab = graph["package"]
    assert lab["revision"] == @revision
    assert lab["source_url"] == "https://github.com/wotex-project/wotex-lab/tree/" <> @revision
    assert lab["artifact"] == %{"hex_observation" => "not_published", "archive_sha256" => nil}
    assert lab["source_digest"] =~ ~r/\Asha256:[0-9a-f]{64}\z/
    assert lab["completion_plan_sha256"] =~ @hex

    wlb07 = Enum.find(graph["specifications"], &(&1["id"] == "WLB.07"))
    catalogue_wlb07 = Enum.find(catalogue["specifications"], &(&1["id"] == "WLB.07"))
    assert wlb07["implementation_status"] == catalogue_wlb07["implementation_status"]
    assert wlb07["evidence_status"] == catalogue_wlb07["evidence_status"]
    assert wlb07["source_url"] =~ @revision and wlb07["sha256"] =~ @hex
    assert graph["lab_status"]["implementation_status"] == catalogue_wlb07["implementation_status"]

    upstream = Enum.find(graph["specifications"], &(&1["id"] == "wotex:WTX.01"))
    wotex = Enum.find(index["packages"], &(&1["package"] == "wotex"))
    assert upstream["implementation_status"] == "implemented"
    assert upstream["evidence_status"] == "not_reported"
    assert upstream["adoption_status"] == "not_reported"
    assert upstream["snapshot"] == true and upstream["revision"] == wotex["revision"]
    assert upstream["provenance_role"] == "historical_baseline"

    assert upstream["source_url"] ==
             "#{wotex["repository"]}/blob/#{wotex["revision"]}/#{upstream["path"]}"

    assert upstream["observed_on"] == index["observed_on"]

    overlay =
      Enum.find(graph["evidence_overlays"], &(&1["id"] == "wotex_lab:cookbook:parse-td"))

    assert overlay["namespace"] == "wotex_lab"
    assert overlay["producer"] == "wotex_lab"
    assert overlay["closure_authority"] == "package_owner"
    assert overlay["status"] == "executable"
    assert "WLB-C03" in overlay["completion_ids"]
    assert "wotex:WTX-C01" in overlay["completion_ids"]
    assert overlay["evidence_sources"] == ["priv/cookbooks/parse-td.livemd"]

    overlay_node =
      Enum.find(
        graph["nodes"],
        &(&1["id"] == "evidence_overlay:wotex_lab:cookbook:parse-td")
      )

    assert overlay_node["type"] == "evidence_overlay"

    assert %{
             "from" => "evidence_overlay:wotex_lab:cookbook:parse-td",
             "to" => "completion:wotex:WTX-C01",
             "relation" => "indexes"
           } in graph["edges"]

    package = Enum.find(graph["packages"], &(&1["name"] == "wotex"))
    assert package["catalogue_sha256"] == wotex["catalogue_sha256"]
    assert package["cohort_sha256"] =~ @hex and is_integer(package["cohort_files"])
    assert package["artifact"]["hex_observation"] == "not_available"

    fixture = Enum.find(graph["fixtures"], &(&1["id"] == "thermal-nx"))
    assert fixture["input_sha256"] =~ @hex and fixture["expected_output_sha256"] =~ @hex
    assert fixture["media_type"] == "application/td+json" and fixture["license"] == "Apache-2.0"
    assert fixture["vectors"]["negative"] != [] and fixture["scenario"] == "thermal-nx"

    cookbook = Enum.find(graph["cookbooks"], &(&1["id"] == "formal-control"))
    assert cookbook["lane"] == "implemented" and cookbook["evidence"] == "executable"
    assert cookbook["source_url"] =~ "priv/cookbooks/formal-control.livemd"

    formal_seam = Enum.find(graph["seams"], &(&1["id"] == "lab.formal_verification"))

    assert formal_seam["status"] == "implemented" and
             formal_seam["module"] == "Wotex.Lab.Formal.Profile"

    kinds = graph["documents"] |> Enum.map(& &1["kind"]) |> Enum.uniq() |> Enum.sort()
    assert kinds == ~w(completion_plan cookbook decision provenance readme specification)
    assert Enum.all?(graph["documents"], &(&1["sha256"] =~ @hex and &1["title"] != "untitled"))
  end

  test "every representation renders, decodes and declares its dialect", %{graph: graph} do
    for {key, path} <- Graph.representations() do
      assert {:ok, content} = Graph.render(graph, key)
      assert is_binary(content) and byte_size(content) > 0, "#{path} rendered nothing"
    end

    {:ok, well_known} = Graph.render(graph, :well_known)
    {:ok, decoded} = Wotex.JSON.decode(well_known)
    assert decoded["kind"] == "wotex_lab_well_known" and decoded["deployment"] == "none"
    assert decoded["representations"]["manifest"] == "/manifest.json"

    {:ok, manifest} = Graph.render(graph, :manifest)
    {:ok, decoded} = Wotex.JSON.decode(manifest)
    assert length(decoded["nodes"]) == length(graph["nodes"])

    {:ok, jsonld} = Graph.render(graph, :manifest_jsonld)
    {:ok, decoded} = Wotex.JSON.decode(jsonld)
    assert decoded["@context"]["@version"] == 1.1 and decoded["@context"]["wl"] =~ "wotex.io"
    assert length(decoded["@graph"]) == length(graph["nodes"])
    node = Enum.find(decoded["@graph"], &(&1["@id"] == "urn:wotex:lab:graph:adapter:req_client"))
    assert node["@type"] == "wl:Adapter"
    assert node["wl:implements"] == [%{"@id" => "urn:wotex:lab:graph:seam:http.client"}]

    {:ok, turtle} = Graph.render(graph, :ecosystem_ttl)
    assert :ok = Render.check_turtle(turtle)
    assert turtle =~ "@prefix wl: <https://wotex.io/lab/graph#> ."
    assert turtle =~ "<urn:wotex:lab:graph:spec:wotex:WTX.01> a wl:Specification ;"
    assert turtle =~ ~s(wl:evidenceStatus "not_reported" ;)

    {:ok, fixtures} = Graph.render(graph, :fixtures_index)
    {:ok, decoded} = Wotex.JSON.decode(fixtures)
    assert length(decoded["fixtures"]) == 6

    {:ok, docs} = Graph.render(graph, :docs_index)
    lines = String.split(docs, "\n", trim: true)
    assert length(lines) == length(graph["documents"])
    assert Enum.all?(lines, &match?({:ok, %{"path" => _}}, Wotex.JSON.decode(&1)))

    {:ok, openapi} = Graph.render(graph, :openapi)
    {:ok, decoded} = Wotex.JSON.decode(openapi)

    assert decoded["openapi"] == "3.2.0" and
             decoded["x-wotex-deployment"] == "optional-workbench-host"

    assert decoded["servers"] == [%{"description" => "Workbench host", "url" => "/api/v1"}]

    assert decoded["paths"]["/evidence/{record_id}"]["get"]["security"] == [
             %{"sessionBearer" => []}
           ]

    assert Map.keys(decoded["paths"]) |> Enum.sort() == [
             "/evidence/{record_id}",
             "/metrics/catalogue",
             "/metrics/query",
             "/runs",
             "/runs/{run_id}",
             "/runs/{run_id}/approval",
             "/runs/{run_id}/cancel",
             "/scenarios",
             "/scenarios/{id}"
           ]

    mutations =
      for {_, %{"post" => operation}} <- decoded["paths"],
          Map.has_key?(operation, "x-wotex-opt-in"),
          do: operation

    assert Enum.map(mutations, & &1["operationId"]) |> Enum.sort() ==
             ["approveDecision", "cancelRun", "startRun"]

    for operation <- mutations do
      assert operation["x-wotex-opt-in"] == "control_mutations"
      assert operation["security"] == [%{"sessionBearer" => []}]
      assert %{"$ref" => "#/components/parameters/IdempotencyKey"} in operation["parameters"]
      assert operation["responses"]["429"]["headers"]["Retry-After"]
      [schema] = Map.values(operation["requestBody"]["content"])
      name = schema["schema"]["$ref"] |> String.split("/") |> List.last()
      assert decoded["components"]["schemas"][name]["additionalProperties"] == false
      assert "deadline_ms" in decoded["components"]["schemas"][name]["required"]
    end

    query = decoded["paths"]["/metrics/query"]["post"]

    assert query["operationId"] == "queryMetrics" and
             query["security"] == [%{"sessionBearer" => []}]

    refute Map.has_key?(query, "x-wotex-opt-in") or Map.has_key?(query, "parameters")
    request = decoded["components"]["schemas"]["MetricQueryRequest"]
    assert request["additionalProperties"] == false

    assert request["properties"] |> Map.keys() |> Enum.sort() ==
             Enum.sort(
               ~w(schema_version metric aggregation filters quantile start_at end_at step_ms)
             )

    assert request["properties"]["aggregation"]["enum"] ==
             Enum.map(Wotex.Lab.Metrics.Query.aggregations(), &Atom.to_string/1)

    metrics_status =
      Enum.find(graph["specifications"], &(&1["id"] == "WLB.10"))["implementation_status"]

    assert decoded["paths"]["/metrics/catalogue"]["get"]["x-wotex-status"]["implementation_status"] ==
             metrics_status

    {:ok, asyncapi} = Graph.render(graph, :asyncapi)
    parsed = YamlElixir.read_from_string!(asyncapi)
    assert parsed == Interfaces.asyncapi(graph)
    assert parsed["asyncapi"] == "3.1.0" and parsed["x-wotex-deployment"] == "none"
    assert parsed["channels"]["temperature"]["address"] == "{prefix}/properties/temperature"

    {:ok, llms} = Graph.render(graph, :llms)
    assert String.starts_with?(llms, "# Wotex Lab\n")
    assert llms =~ "not_reported" and llms =~ "parse-td" and llms =~ "Who owns HTTP redirects?"

    assert {:error, %Error{code: :unknown_representation}} = Graph.render(graph, :nope)
  end

  test "write places every representation under its endpoint path", %{graph: graph} do
    directory = tmp("write")
    assert {:ok, files} = Graph.write(graph, directory)
    assert length(files) == 9
    assert File.regular?(Path.join(directory, ".well-known/wotex"))
    assert File.regular?(Path.join(directory, "fixtures/index.json"))

    blocked = tmp("blocked")
    File.write!(blocked, "not a directory")
    assert {:error, %Error{code: :write_failed}} = Graph.write(graph, blocked)
  end

  test "ownership questions resolve package, spec, seam, ownership, source and fixture", %{
    graph: graph
  } do
    for question <- Graph.questions() do
      assert {:ok, answer} = Graph.answer(graph, question)

      for key <- ~w(package spec seam ownership fixture fixture_digest statement status) do
        refute is_nil(answer[key]), "#{question} lacks #{key}"
      end
    end

    {:ok, redirects} = Graph.answer(graph, :redirects)

    assert redirects["seam"] == "seam:http.client" and
             redirects["ownership"] == "consumer-implements"

    assert redirects["adapter"] == "adapter:req_client"

    assert redirects["canonical_source"] =~ @revision and
             redirects["canonical_source"] =~ "req_client.ex"

    assert redirects["fixture"] == "fixture:http-room"

    {:ok, reconnect} = Graph.answer(graph, :reconnect)
    assert reconnect["seam"] == "seam:runtime.credentials" and reconnect["statement"] =~ "restart"

    {:ok, supervision} = Graph.answer(graph, :supervision)
    assert supervision["seam"] == "seam:lab.instance" and supervision["spec"] == "spec:WLB.01"

    {:ok, remote} = Graph.answer(graph, :remote_contexts)

    assert remote["package"] == "package:wotex_continuum" and
             remote["spec"] == "spec:wotex_continuum:WCT.01"

    assert remote["status"]["evidence_status"] == "not_reported"

    {:ok, storage} = Graph.answer(graph, :directory_storage)

    assert storage["seam"] == "seam:directory.repository" and
             storage["adapter"] == "adapter:sqlite_repository"

    {:ok, effects} = Graph.answer(graph, :nx_effects)
    assert effects["seam"] == "seam:lab.policy" and effects["ownership"] == "lab-owned"

    {:ok, intent} = Graph.answer(graph, :continuum_intent)
    assert intent["adapter"] == "adapter:channel" and intent["statement"] =~ "at most once"

    {:ok, formal} = Graph.answer(graph, :formal_verification)

    assert formal["seam_status"] == "implemented" and
             formal["status"]["implementation_status"] == "implemented"

    assert formal["adapter"] == nil
    assert formal["canonical_source"] =~ "lib/wotex/lab/formal/profile.ex"

    assert {:error, %Error{code: :unknown_question}} = Graph.answer(graph, :who_knows)

    truncated = %{
      graph
      | "nodes" => Enum.reject(graph["nodes"], &(&1["id"] == "fixture:http-room"))
    }

    assert {:error, %Error{code: :unresolved_id}} = Graph.answer(truncated, :redirects)
  end

  test "malformed inputs are refused before any file is read", %{catalogue: catalogue} do
    assert {:error, %Error{code: :invalid_input}} =
             Graph.generate(catalogue: catalogue, revision: @revision)

    assert {:error, %Error{code: :invalid_input}} =
             Graph.generate(catalogue: catalogue, revision: @revision, root: tmp("empty"))

    assert {:error, %Error{code: :invalid_input}} =
             Graph.generate(catalogue: %{}, revision: @revision, root: @root)

    assert {:error, %Error{code: :invalid_input}} =
             Graph.generate(catalogue: catalogue, revision: "abc", root: @root)

    assert {:error, %Error{code: :invalid_input}} =
             Graph.generate(catalogue: catalogue, revision: nil, root: @root)

    assert {:error, %Error{code: :unresolved_path}} =
             generate(%{catalogue | "source_index" => "priv/provenance/nope.json"})

    assert {:error, %Error{code: :unresolved_path}} =
             generate(%{catalogue | "completion_plan" => "docs/plans/nope.md"})

    assert {:error, %Error{code: :unresolved_path}} =
             generate(%{catalogue | "completion_plan" => "docs/../mix.exs"})

    assert {:error, %Error{code: :unresolved_path}} =
             generate(%{catalogue | "completion_plan" => "../../etc/passwd"})
  end

  test "duplicate, unresolved, cyclic and undeclared descriptors are rejected", %{
    catalogue: catalogue
  } do
    [first | _] = scenarios = Descriptors.scenarios()
    [adapter | adapters] = Descriptors.adapters()

    assert {:error, %Error{code: :duplicate_id, details: %{id: "scenario:parse-td"}}} =
             generate(catalogue, scenarios: scenarios ++ [first])

    assert {:error, %Error{code: :unresolved_id, details: %{id: "adapter:ghost"}}} =
             generate(catalogue, scenarios: [%{first | adapters: ["ghost"]} | tl(scenarios)])

    assert {:error, %Error{code: :unresolved_id, details: %{id: "spec:WLB.99"}}} =
             generate(catalogue, cookbooks: cookbooks_with(specs: ["WLB.99"]))

    assert {:error, %Error{code: :unresolved_id, details: %{id: "completion:unknown:ZZ-C01"}}} =
             generate(catalogue, cookbooks: cookbooks_with(upstream: ["ZZ-C01"]))

    assert {:error, %Error{code: :unresolved_path, details: %{path: "lib/nope.ex"}}} =
             generate(catalogue, adapters: [%{adapter | path: "lib/nope.ex"} | adapters])

    assert {:error, %Error{code: :undeclared_ownership_change, details: %{adapter: "loopback"}}} =
             generate(catalogue,
               adapters: [%{adapter | ownership: "package-implements"} | adapters]
             )

    [seam | seams] = Descriptors.seams()

    assert {:error, %Error{code: :unresolved_callback, details: %{seam: "lab.instance"}}} =
             generate(catalogue, seams: [%{seam | callbacks: ["nope/9"]} | seams])

    assert {:error, %Error{code: :unresolved_callback}} =
             generate(catalogue, seams: [%{seam | module: "Wotex.Lab.Nope"} | seams])

    cyclic =
      Enum.map(scenarios, fn scenario ->
        case scenario.id do
          "parse-td" -> %{scenario | requires: ["thermal-nx"]}
          other when other != "parse-td" -> scenario
        end
      end)

    assert {:error, %Error{code: :scenario_cycle, details: %{path: path}}} =
             generate(catalogue, scenarios: cyclic)

    assert "scenario:parse-td" in path

    steps = [%{id: "x", requires: ["y"]}, %{id: "y", requires: ["x"]}]

    assert {:error, %Error{code: :scenario_cycle}} =
             generate(catalogue, scenarios: [%{first | steps: steps} | tl(scenarios)])
  end

  test "tampered fixtures and unreadable inputs are rejected from a copied root", %{
    catalogue: catalogue
  } do
    root = tmp("copy")

    File.mkdir_p!(Path.join(root, "priv"))

    # Copy source inputs only. Host docs/build output can change concurrently
    # and must never become part of this fixture's source snapshot. The
    # documentation tree is copied beside mix.exs, the standalone layout.
    for entry <-
          ~w(lib test bin clients hosts/workbench/lib hosts/workbench/test hosts/workbench/bin
             hosts/nerves/test
             priv/fixtures priv/cookbooks priv/provenance priv/conformance/native/src
             priv/conformance/native/tests priv/conformance/native/probes
             priv/conformance/native/Cargo.toml priv/conformance/native/Cargo.lock
             README.md CHANGELOG.md mix.exs) do
      target = Path.join(root, entry)
      File.mkdir_p!(Path.dirname(target))
      File.cp_r!(Path.join(@root, entry), target)
    end

    File.cp_r!(@docs, Path.join(root, "docs"))

    for excluded <- ~w(hosts/workbench/doc hosts/workbench/_build hosts/workbench/deps
                       priv/conformance/native/target) do
      refute File.exists?(Path.join(root, excluded))
    end

    assert {:ok, _} = generate(catalogue, root: root)

    thermal = Path.join(root, "priv/fixtures/thermal/thing-description.json")
    File.write!(thermal, File.read!(thermal) <> "\n")

    assert {:error, %Error{code: :digest_mismatch, details: %{fixture: "thermal-nx"}}} =
             generate(catalogue, root: root)

    File.rm!(thermal)

    assert {:error, %Error{code: :unresolved_path, details: %{fixture: "thermal-nx"}}} =
             generate(catalogue, root: root)

    manifest = Path.join(root, "priv/fixtures/thermal/manifest.json")
    File.write!(manifest, ~s({"id":"thermal-nx","specs":[],"seams":[],"vectors":{}}))
    assert {:error, %Error{code: :unresolved_path}} = generate(catalogue, root: root)

    File.write!(manifest, "{not json")
    assert {:error, %Error{code: :unreadable_input}} = generate(catalogue, root: root)

    # A fixture an ownership question names cannot disappear silently.
    File.rm_rf!(Path.join(root, "priv/fixtures/thermal"))

    assert {:error, %Error{code: :unresolved_id, details: %{id: "fixture:thermal-nx"}}} =
             generate(catalogue, root: root)

    File.cp_r!(Path.join(@root, "priv/fixtures/thermal"), Path.join(root, "priv/fixtures/thermal"))
    File.rm_rf!(Path.join(root, "priv/fixtures/mqtt"))
    File.write!(Path.join(root, "docs/decisions/untitled.md"), "no heading here\n")
    assert {:ok, graph} = generate(catalogue, root: root)
    assert Enum.any?(graph["documents"], &(&1["title"] == "untitled"))
    assert length(graph["fixtures"]) == 5
    assert Interfaces.asyncapi(graph)["x-wotex-fixture"] == nil
  end

  test "the YAML emitter is deterministic and round-trips through a YAML parser" do
    value = %{
      "b" => [1, "two", %{"c" => nil, "d" => true}, [], %{}],
      "a" => %{"quoted" => ~s(say "hi": now), "n" => -1.5},
      "e" => []
    }

    yaml = Render.yaml(value)
    assert yaml == Render.yaml(value)
    assert String.starts_with?(yaml, "\"a\":\n")
    assert YamlElixir.read_from_string!(yaml) == value
    assert Render.yaml("scalar") == "\"scalar\"\n"
  end

  test "the Turtle check refuses undeclared prefixes, unterminated statements and noise" do
    good =
      "@prefix wl: <https://wotex.io/lab/graph#> .\n\n<urn:a> a wl:Thing ;\n    wl:label \"x\" .\n"

    assert :ok = Render.check_turtle(good)

    assert {:error, {:undeclared_prefix, "ex:Thing"}} =
             Render.check_turtle(
               "@prefix wl: <https://wotex.io/lab/graph#> .\n\n<urn:a> a ex:Thing .\n"
             )

    assert {:error, {:unterminated, _}} =
             Render.check_turtle(
               "@prefix wl: <https://wotex.io/lab/graph#> .\n\n<urn:a> a wl:Thing\n"
             )

    assert {:error, {:unparsed, "{oops}"}} =
             Render.check_turtle(
               "@prefix wl: <https://wotex.io/lab/graph#> .\n\n<urn:a> a wl:Thing {oops} .\n"
             )
  end

  test "descriptor questions and graph questions agree" do
    assert Enum.map(Descriptors.questions(), & &1.id) == Graph.questions()

    assert Enum.all?(
             Descriptors.adapters(),
             &(&1.ownership in ["consumer-implements", "lab-owned"])
           )

    assert Descriptors.repository() =~ "wotex-lab"
  end

  defp generate(catalogue, opts \\ []) do
    Graph.generate(
      Keyword.merge(
        [catalogue: catalogue, revision: @revision, root: @root, generated_at: @generated_at],
        opts
      )
    )
  end

  defp cookbooks_with(changes) do
    [first | rest] = Cookbook.list()
    [Map.merge(first, Map.new(changes)) | rest]
  end

  defp tmp(name) do
    parent =
      Path.join(
        System.tmp_dir!(),
        "wotex-lab-graph-" <> Base.encode16(:crypto.strong_rand_bytes(16))
      )

    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf(parent) end)
    Path.join(parent, name)
  end
end
