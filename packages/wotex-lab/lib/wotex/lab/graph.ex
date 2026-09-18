defmodule Wotex.Lab.Graph do
  @moduledoc """
  The generator for the versioned JSON source and evidence graph of WLB.06–07.

  `generate/1` joins the Lab specification catalogue (decoded by the caller),
  the completion plan, the upstream package catalogues recorded in the
  historical provenance source baseline and current source content cohort, the cookbook catalogue, the
  fixture manifests and the Lab scenario, adapter and seam descriptors into
  one graph of nodes and edges. Lab evidence is a separately namespaced overlay
  that indexes exact completion nodes without changing their status or claiming
  closure for another package. Upstream statuses are copied verbatim with
  their revision, digests and observation date; axes absent upstream stay
  `not_reported`. Every input file is digested and every Lab or upstream
  source node carries a revision-specific source URL. Nothing is fetched from
  the network at any time.

  Generation rejects unresolved identifiers, paths and callbacks, duplicate
  identifiers, undeclared ownership changes between an adapter and its seam,
  and cycles in required scenario steps, each with a typed `Wotex.Lab.Error`.
  `render/2` and `write/2` produce the accepted representations, and
  `answer/2` resolves the WLB.07 ownership questions from the graph nodes.

  Catalogue paths that start with `docs/` name the package documentation tree
  located by `Wotex.Lab.Documentation` (`docs/` beside `mix.exs` in a
  standalone checkout, `docs/packages/wotex-lab/` in the monorepo); document
  nodes keep that `docs/<kind>/` form so specification and document
  identifiers agree in both layouts.
  """

  alias Wotex.JSON
  alias Wotex.Lab.{Cookbook, Documentation, Error}
  alias Wotex.Lab.Evidence.Digest
  alias Wotex.Lab.Graph.{Descriptors, Interfaces, Render}

  @schema_version "1.0.0"
  @generator_version "1.0.0"
  @revision ~r/\A[0-9a-f]{40}\z/
  # Bare upstream ids in fixtures and cookbooks are named by their package here.
  @upstream_prefixes %{
    "WTX" => "wotex",
    "WNX" => "wotex_nx",
    "WRT" => "wotex_runtime",
    "RT" => "wotex_runtime",
    "WBH" => "wotex_binding_http",
    "WBM" => "wotex_binding_mqtt",
    "WTD" => "wotex_directory",
    "WCT" => "wotex_continuum",
    "WCF" => "wotex_conformance"
  }
  @apps ~w(wotex_lab wotex wotex_nx wotex_runtime wotex_binding_http wotex_binding_mqtt wotex_directory wotex_continuum wotex_conformance)a
  @source_patterns ~w(lib/**/* priv/**/* mix.exs README.md CHANGELOG.md)
  @document_patterns ~w(README.md priv/cookbooks/*.livemd)
  @document_kind ~r{\Adocs/(?:packages/[^/]+/)?(specs|plans|decisions|provenance)/}
  @representations [
    well_known: "/.well-known/wotex",
    manifest: "/manifest.json",
    manifest_jsonld: "/manifest.jsonld",
    ecosystem_ttl: "/ecosystem.ttl",
    fixtures_index: "/fixtures/index.json",
    docs_index: "/docs-index.jsonl",
    openapi: "/openapi.json",
    asyncapi: "/asyncapi.yaml",
    llms: "/llms.txt"
  ]

  @type representation ::
          :well_known
          | :manifest
          | :manifest_jsonld
          | :ecosystem_ttl
          | :fixtures_index
          | :docs_index
          | :openapi
          | :asyncapi
          | :llms

  @type question ::
          :redirects
          | :reconnect
          | :supervision
          | :remote_contexts
          | :directory_storage
          | :nx_effects
          | :continuum_intent
          | :formal_verification

  @doc "The accepted representations and their endpoint paths."
  @spec representations() :: [{representation(), String.t()}]
  def representations, do: @representations

  @doc "The ownership questions the graph answers."
  @spec questions() :: [question()]
  def questions, do: Enum.map(Descriptors.questions(), & &1.id)

  @doc """
  Generates the graph.

  Options: `:catalogue` (required, the decoded `docs/specs/catalogue.yaml`),
  `:revision` (required, the 40-hex Lab source revision the source URLs name),
  `:root` (required, the Lab source checkout with its documentation tree:
  the catalogue's executable evidence names test sources that a package
  archive does not ship, so an unpacked archive is refused with
  `:unresolved_path`, and the compiled application directory has no
  documentation at all), `:generated_at` (a
  `DateTime`), and
  descriptor overrides `:scenarios`, `:adapters`, `:seams`, `:cookbooks` for
  hosts that add their own.
  """
  @spec generate(keyword()) :: {:ok, map()} | {:error, Error.t()}
  def generate(opts) when is_list(opts) do
    with {:ok, root} <- root(Keyword.get(opts, :root)),
         {:ok, catalogue} <- catalogue(Keyword.get(opts, :catalogue)),
         {:ok, revision} <- revision(Keyword.get(opts, :revision)),
         {:ok, index} <- read_json(root, catalogue["source_index"]),
         {:ok, cohort} <- read_json(root, catalogue["source_cohort"]),
         {:ok, plan} <- read_file(root, catalogue["completion_plan"]),
         {:ok, fixtures} <- fixtures(root),
         {:ok, documents} <- documents(root, revision),
         {:ok, source_digest} <- Digest.tree(root, @source_patterns) |> wrap(:root),
         inputs = %{
           root: root,
           revision: revision,
           catalogue: catalogue,
           index: index,
           cohort: cohort,
           plan: plan,
           fixtures: fixtures,
           documents: documents,
           source_digest: source_digest,
           generated_at: Keyword.get(opts, :generated_at, DateTime.utc_now()),
           scenarios: Keyword.get(opts, :scenarios, Descriptors.scenarios()),
           adapters: Keyword.get(opts, :adapters, Descriptors.adapters()),
           seams: Keyword.get(opts, :seams, Descriptors.seams()),
           cookbooks: Keyword.get(opts, :cookbooks, Cookbook.list())
         },
         graph = assemble(inputs),
         :ok <- validate(graph, inputs) do
      {:ok, graph}
    end
  end

  @doc "Renders one representation as a binary."
  @spec render(map(), representation()) :: {:ok, binary()} | {:error, Error.t()}
  def render(graph, :well_known), do: encode(Render.well_known(graph))
  def render(graph, :manifest), do: encode(graph)
  def render(graph, :manifest_jsonld), do: encode(Render.jsonld(graph))
  def render(graph, :ecosystem_ttl), do: {:ok, Render.turtle(graph)}
  def render(graph, :fixtures_index), do: encode(Render.fixtures_index(graph))
  def render(graph, :docs_index), do: {:ok, Render.docs_index(graph)}
  def render(graph, :openapi), do: encode(Interfaces.openapi(graph))
  def render(graph, :asyncapi), do: {:ok, Render.yaml(Interfaces.asyncapi(graph))}
  def render(graph, :llms), do: {:ok, Render.llms(graph)}

  def render(_, _),
    do: {:error, Error.new(:unknown_representation, :render, "representation is not accepted")}

  @doc "Writes every representation under `directory` using its endpoint path; returns the files."
  @spec write(map(), Path.t()) :: {:ok, [Path.t()]} | {:error, Error.t()}
  def write(graph, directory) when is_binary(directory) do
    written =
      Enum.reduce_while(@representations, {:ok, []}, fn {key, path}, {:ok, written} ->
        file = Path.join(directory, String.trim_leading(path, "/"))

        with {:ok, content} <- render(graph, key),
             :ok <- File.mkdir_p(Path.dirname(file)),
             :ok <- File.write(file, content) do
          {:cont, {:ok, [file | written]}}
        else
          {:error, %Error{} = error} -> {:halt, {:error, error}}
          {:error, reason} -> {:halt, {:error, Error.new(:write_failed, :render, inspect(reason))}}
        end
      end)

    with {:ok, files} <- written, do: {:ok, Enum.reverse(files)}
  end

  @doc "Answers an ownership question from the graph with resolved package, spec, seam, source and fixture ids."
  @spec answer(map(), question()) :: {:ok, map()} | {:error, Error.t()}
  def answer(graph, question) when is_atom(question) do
    case Enum.find(graph["questions"], &(&1["id"] == Atom.to_string(question))) do
      nil ->
        {:error, Error.new(:unknown_question, :retrieval, "question is not in the corpus")}

      entry ->
        resolve_answer(graph, entry)
    end
  end

  defp resolve_answer(graph, entry) do
    with {:ok, package} <- node(graph, "package:" <> entry["package"]),
         {:ok, spec} <- node(graph, "spec:" <> entry["spec"]),
         {:ok, seam} <- node(graph, "seam:" <> entry["seam"]),
         {:ok, fixture} <- node(graph, "fixture:" <> entry["fixture"]),
         {:ok, adapter} <- optional_node(graph, "adapter:", entry["adapter"]) do
      {:ok,
       %{
         "question" => entry["question"],
         "statement" => entry["statement"],
         "package" => package["id"],
         "spec" => spec["id"],
         "status" =>
           Map.take(spec, ["implementation_status", "evidence_status", "adoption_status"]),
         "seam" => seam["id"],
         "ownership" => seam["ownership"],
         "seam_status" => seam["status"],
         "adapter" => adapter && adapter["id"],
         # A planned seam has no module yet; its specification is the source that exists.
         "canonical_source" =>
           (adapter && adapter["source_url"]) || seam["source_url"] || spec["source_url"],
         "fixture" => fixture["id"],
         "fixture_digest" => fixture["input_sha256"]
       }}
    end
  end

  defp assemble(inputs) do
    lab = lab_package(inputs)
    upstream = Enum.map(inputs.index["packages"], &upstream_package(&1, inputs))
    specifications = lab_specifications(inputs) ++ upstream_specifications(inputs)
    completions = completions(inputs)
    seams = seams(inputs)
    adapters = Enum.map(inputs.adapters, &adapter(&1, inputs))
    scenarios = Enum.map(inputs.scenarios, &scenario/1)
    cookbooks = Enum.map(inputs.cookbooks, &cookbook(&1, inputs))
    evidence_overlays = evidence_overlays(specifications, cookbooks)
    questions = Enum.map(Descriptors.questions(), &question/1)

    lab_status =
      specifications
      |> Enum.find(&(&1["id"] == "WLB.07"))
      |> status_axes()

    nodes =
      Enum.map([lab | upstream], &node_of("package", &1)) ++
        Enum.map(specifications, &node_of("specification", &1)) ++
        Enum.map(completions, &node_of("completion", &1)) ++
        Enum.map(seams, &node_of("seam", &1)) ++
        Enum.map(adapters, &node_of("adapter", &1)) ++
        Enum.map(scenarios, &node_of("scenario", &1)) ++
        Enum.map(cookbooks, &node_of("cookbook", &1)) ++
        Enum.map(evidence_overlays, &node_of("evidence_overlay", &1)) ++
        Enum.map(inputs.fixtures, &node_of("fixture", &1)) ++
        Enum.map(inputs.documents, &node_of("document", &1))

    %{
      "schema_version" => @schema_version,
      "kind" => "wotex_lab_source_graph",
      "snapshot" => true,
      "provenance" => %{
        "source_index_role" => inputs.index["role"],
        "source_cohort_kind" => inputs.cohort["kind"]
      },
      "generated_at" => DateTime.to_iso8601(inputs.generated_at),
      "generator" => %{
        "module" => "Wotex.Lab.Graph",
        "version" => @generator_version,
        "elixir" => System.version(),
        "openapi" => Interfaces.openapi_version(),
        "asyncapi" => Interfaces.asyncapi_version(),
        "jsonld" => "1.1",
        "turtle" => "RDF 1.1"
      },
      "representations" =>
        Map.new(@representations, fn {key, path} -> {Atom.to_string(key), path} end),
      "package" => lab,
      "lab_status" => lab_status,
      "packages" => [lab | upstream],
      "specifications" => specifications,
      "completions" => completions,
      "seams" => seams,
      "adapters" => adapters,
      "scenarios" => scenarios,
      "cookbooks" => cookbooks,
      "evidence_overlays" => evidence_overlays,
      "fixtures" => inputs.fixtures,
      "documents" => inputs.documents,
      "questions" => questions,
      "nodes" => nodes,
      "edges" =>
        edges(
          specifications,
          seams,
          adapters,
          scenarios,
          cookbooks,
          evidence_overlays,
          inputs.fixtures
        )
    }
  end

  defp lab_package(inputs) do
    %{
      "id" => "package:wotex_lab",
      "name" => "wotex_lab",
      "version" => to_string(Application.spec(:wotex_lab, :vsn) || "0.0.0"),
      "repository" => Descriptors.repository(),
      "revision" => inputs.revision,
      "source_url" => source_url(Descriptors.repository(), inputs.revision, nil),
      "source_digest" => inputs.source_digest,
      "catalogue" => inputs.catalogue["schema_version"],
      "completion_plan" => inputs.catalogue["completion_plan"],
      "completion_plan_sha256" => sha256(inputs.plan),
      "artifact" => %{"hex_observation" => "not_published", "archive_sha256" => nil},
      "observed_on" => inputs.index["observed_on"],
      "snapshot" => true
    }
  end

  defp upstream_package(package, inputs) do
    cohort = Enum.find(inputs.cohort["packages"], &(&1["package"] == package["package"])) || %{}

    %{
      "id" => "package:" <> package["package"],
      "name" => package["package"],
      "repository" => package["repository"],
      "revision" => package["revision"],
      "source_url" => source_url(package["repository"], package["revision"], nil),
      "catalogue" => package["catalogue"],
      "catalogue_sha256" => package["catalogue_sha256"],
      "completion_plan" => package["completion_plan"],
      "completion_plan_sha256" => package["completion_plan_sha256"],
      "completion_ids" => package["completion_ids"],
      "artifact" => package["artifact"],
      "cohort_files" => cohort["files"],
      "cohort_sha256" => cohort["sha256"],
      "observed_on" => inputs.index["observed_on"],
      "provenance_role" => inputs.index["role"],
      "snapshot" => true
    }
  end

  defp lab_specifications(inputs) do
    Enum.map(inputs.catalogue["specifications"], fn spec ->
      %{
        "id" => spec["id"],
        "package" => "wotex_lab",
        "version" => spec["version"],
        "path" => spec["path"],
        "sha256" => file_sha256(inputs.root, spec["path"]),
        "source_url" => source_url(Descriptors.repository(), inputs.revision, spec["path"]),
        "implementation_status" => spec["implementation_status"],
        "evidence_status" => spec["evidence_status"],
        "adoption_status" => spec["adoption_status"],
        "requires" => spec["requires"],
        "completion_items" => spec["completion_items"],
        "implementation_modules" => spec["implementation_modules"],
        "executable_evidence" => spec["executable_evidence"],
        "evidence_manifest" => spec["evidence_manifest"],
        "standards" => spec["standards"],
        "compatibility_classification" => spec["compatibility_classification"],
        "snapshot" => false
      }
    end)
  end

  defp upstream_specifications(inputs) do
    Enum.flat_map(inputs.index["packages"], fn package ->
      Enum.map(package["specifications"], fn spec ->
        %{
          "id" => package["package"] <> ":" <> spec["id"],
          "package" => package["package"],
          "version" => spec["version"],
          "path" => spec["path"],
          "source_url" => source_url(package["repository"], package["revision"], spec["path"]),
          "implementation_status" => spec["implementation_status"],
          "evidence_status" => Map.get(spec, "evidence_status", "not_reported"),
          "adoption_status" => Map.get(spec, "adoption_status", "not_reported"),
          "revision" => package["revision"],
          "catalogue_sha256" => package["catalogue_sha256"],
          "observed_on" => inputs.index["observed_on"],
          "provenance_role" => inputs.index["role"],
          "snapshot" => true
        }
      end)
    end)
  end

  defp completions(inputs) do
    lab =
      ~r/\| (WLB-C\d+) \| ([^|]*) \| ([^|]*) \|/
      |> Regex.scan(inputs.plan)
      |> Enum.map(fn [_, id, prerequisites, deliverable] ->
        %{
          "id" => id,
          "package" => "wotex_lab",
          "prerequisites" => String.trim(prerequisites),
          "deliverable" => String.trim(deliverable),
          "plan" => inputs.catalogue["completion_plan"],
          "plan_sha256" => sha256(inputs.plan)
        }
      end)

    upstream =
      Enum.flat_map(inputs.index["packages"], fn package ->
        Enum.map(package["completion_ids"], fn id ->
          %{
            "id" => package["package"] <> ":" <> id,
            "package" => package["package"],
            "plan" => package["completion_plan"],
            "plan_sha256" => package["completion_plan_sha256"]
          }
        end)
      end)

    lab ++ upstream
  end

  defp seams(inputs) do
    upstream =
      Enum.map(inputs.index["seams"], fn seam ->
        %{
          "id" => seam["id"],
          "package" => seam["package"],
          "module" => seam["module"],
          "callbacks" => seam["callbacks"],
          "ownership" => seam["ownership"],
          "path" => seam["path"],
          "source_url" => seam["source_url"],
          "lab_spec" => seam["lab_spec"],
          "status" => "implemented",
          "snapshot" => true
        }
      end)

    lab =
      Enum.map(inputs.seams, fn seam ->
        %{
          "id" => seam.id,
          "package" => seam.package,
          "module" => seam.module,
          "callbacks" => seam.callbacks,
          "ownership" => seam.ownership,
          "path" => seam.path,
          "source_url" =>
            seam.path && source_url(Descriptors.repository(), inputs.revision, seam.path),
          "lab_spec" => seam.lab_spec,
          "status" => seam.status,
          "snapshot" => false
        }
      end)

    upstream ++ lab
  end

  defp adapter(adapter, inputs) do
    %{
      "id" => adapter.id,
      "module" => adapter.module,
      "seam" => adapter.seam,
      "ownership" => adapter.ownership,
      "spec" => adapter.spec,
      "path" => adapter.path,
      "sha256" => file_sha256(inputs.root, adapter.path),
      "source_url" => source_url(Descriptors.repository(), inputs.revision, adapter.path),
      "status" => adapter.status
    }
  end

  defp scenario(scenario) do
    %{
      "id" => scenario.id,
      "title" => scenario.title,
      "spec" => scenario.spec,
      "completion" => scenario.completion,
      "status" => scenario.status,
      "capabilities" => scenario.capabilities,
      "requires" => scenario.requires,
      "adapters" => scenario.adapters,
      "steps" => Enum.map(scenario.steps, &%{"id" => &1.id, "requires" => &1.requires})
    }
  end

  defp cookbook(entry, inputs) do
    %{
      "id" => entry.id,
      "title" => entry.title,
      "path" => entry.path,
      "sha256" => file_sha256(inputs.root, entry.path),
      "source_url" => source_url(Descriptors.repository(), inputs.revision, entry.path),
      "specs" => entry.specs,
      "completion_ids" => entry.completion_ids,
      "upstream" => entry.upstream,
      "lane" => Atom.to_string(entry.lane),
      "evidence" => Atom.to_string(entry.evidence),
      "checks" => entry.checks
    }
  end

  defp evidence_overlays(specifications, cookbooks) do
    specification_entries =
      specifications
      |> Enum.filter(&(&1["package"] == "wotex_lab"))
      |> Enum.map(fn spec ->
        %{
          "id" => "wotex_lab:spec:" <> spec["id"],
          "namespace" => "wotex_lab",
          "producer" => "wotex_lab",
          "source_kind" => "specification",
          "source_id" => spec["id"],
          "status" => spec["evidence_status"],
          "completion_ids" => List.wrap(spec["completion_items"]),
          "evidence_sources" =>
            (List.wrap(spec["executable_evidence"]) ++ List.wrap(spec["evidence_manifest"]))
            |> Enum.uniq(),
          "closure_authority" => "package_owner"
        }
      end)

    cookbook_entries =
      Enum.map(cookbooks, fn cookbook ->
        %{
          "id" => "wotex_lab:cookbook:" <> cookbook["id"],
          "namespace" => "wotex_lab",
          "producer" => "wotex_lab",
          "source_kind" => "cookbook",
          "source_id" => cookbook["id"],
          "status" => cookbook["evidence"],
          "completion_ids" =>
            cookbook["completion_ids"] ++ Enum.map(cookbook["upstream"], &upstream_completion/1),
          "evidence_sources" => [cookbook["path"]],
          "closure_authority" => "package_owner"
        }
      end)

    specification_entries ++ cookbook_entries
  end

  defp question(question) do
    %{
      "id" => Atom.to_string(question.id),
      "question" => question.question,
      "package" => question.package,
      "spec" => question.spec,
      "seam" => question.seam,
      "adapter" => question.adapter,
      "fixture" => question.fixture,
      "statement" => question.statement
    }
  end

  defp edges(specifications, seams, adapters, scenarios, cookbooks, evidence_overlays, fixtures) do
    spec_edges =
      Enum.flat_map(specifications, fn spec ->
        Enum.concat([
          Enum.map(spec["requires"] || [], &edge("spec:" <> spec["id"], "spec:" <> &1, "requires")),
          Enum.map(
            spec["completion_items"] || [],
            &edge("spec:" <> spec["id"], "completion:" <> &1, "delivers")
          ),
          [edge("spec:" <> spec["id"], "package:" <> spec["package"], "owned_by")]
        ])
      end)

    seam_edges =
      Enum.flat_map(seams, fn seam ->
        [
          edge("seam:" <> seam["id"], "package:" <> seam["package"], "owned_by"),
          edge("seam:" <> seam["id"], "spec:" <> seam["lab_spec"], "exercised_by")
        ]
      end)

    adapter_edges =
      Enum.flat_map(adapters, fn adapter ->
        [
          edge("adapter:" <> adapter["id"], "seam:" <> adapter["seam"], "implements"),
          edge("adapter:" <> adapter["id"], "spec:" <> adapter["spec"], "specified_by")
        ]
      end)

    scenario_edges =
      Enum.flat_map(scenarios, fn scenario ->
        Enum.map(
          scenario["requires"],
          &edge("scenario:" <> scenario["id"], "scenario:" <> &1, "requires")
        ) ++
          Enum.map(
            scenario["adapters"],
            &edge("scenario:" <> scenario["id"], "adapter:" <> &1, "uses")
          ) ++
          [
            edge("scenario:" <> scenario["id"], "spec:" <> scenario["spec"], "specified_by"),
            edge("scenario:" <> scenario["id"], "completion:" <> scenario["completion"], "delivers")
          ]
      end)

    cookbook_edges =
      Enum.flat_map(cookbooks, fn cookbook ->
        Enum.concat([
          Enum.map(
            cookbook["specs"],
            &edge("cookbook:" <> cookbook["id"], "spec:" <> &1, "evidences")
          ),
          Enum.map(
            cookbook["completion_ids"],
            &edge("cookbook:" <> cookbook["id"], "completion:" <> &1, "evidences")
          ),
          Enum.map(
            cookbook["upstream"],
            &edge(
              "cookbook:" <> cookbook["id"],
              "completion:" <> upstream_completion(&1),
              "supplies"
            )
          ),
          [edge("cookbook:" <> cookbook["id"], "scenario:" <> cookbook["id"], "runs")]
        ])
      end)

    evidence_overlay_edges =
      Enum.flat_map(evidence_overlays, fn overlay ->
        source = "evidence_overlay:" <> overlay["id"]

        Enum.map(
          overlay["completion_ids"],
          &edge(source, "completion:" <> &1, "indexes")
        ) ++
          [edge(source, "package:" <> overlay["producer"], "produced_by")] ++
          [
            edge(
              source,
              overlay_source(overlay),
              "describes"
            )
          ]
      end)

    fixture_edges =
      Enum.flat_map(fixtures, fn fixture ->
        Enum.concat([
          Enum.map(
            fixture["seams"],
            &edge("fixture:" <> fixture["id"], "seam:" <> &1, "exercises")
          ),
          Enum.map(
            fixture["specs"],
            &edge("fixture:" <> fixture["id"], "spec:" <> spec_ref(&1), "evidences")
          ),
          [edge("fixture:" <> fixture["id"], "scenario:" <> fixture["scenario"], "used_by")]
        ])
      end)

    spec_edges ++
      seam_edges ++
      adapter_edges ++
      scenario_edges ++ cookbook_edges ++ evidence_overlay_edges ++ fixture_edges
  end

  defp overlay_source(%{"source_kind" => "specification", "source_id" => id}), do: "spec:" <> id
  defp overlay_source(%{"source_kind" => "cookbook", "source_id" => id}), do: "cookbook:" <> id

  defp edge(from, to, relation), do: %{"from" => from, "to" => to, "relation" => relation}

  # Upstream ids may be bare (`WTX.01`, `WTX-C01`) in fixtures and cookbooks;
  # the graph names them with their package.
  defp spec_ref(id) do
    case String.split(id, ":", parts: 2) do
      [_, _] -> id
      [bare] -> if String.starts_with?(bare, "WLB."), do: bare, else: prefixed(bare, ".")
    end
  end

  defp upstream_completion(id), do: prefixed(id, "-")

  defp prefixed(id, separator) do
    [prefix | _] = String.split(id, separator, parts: 2)
    Map.get(@upstream_prefixes, prefix, "unknown") <> ":" <> id
  end

  defp validate(graph, inputs) do
    ids = Enum.map(graph["nodes"], & &1["id"])

    with :ok <- unique(ids),
         :ok <- resolved(graph, ids),
         :ok <- paths(graph, inputs.root),
         :ok <- callbacks(graph),
         :ok <- ownership(graph) do
      acyclic(graph["scenarios"])
    end
  end

  defp unique(ids) do
    case ids -- Enum.uniq(ids) do
      [] -> :ok
      [id | _] -> {:error, reject(:duplicate_id, "graph identifiers must be unique", %{id: id})}
    end
  end

  defp resolved(graph, ids) do
    known = MapSet.new(ids)

    unresolved =
      graph["edges"]
      |> Enum.flat_map(&[&1["from"], &1["to"]])
      |> Enum.reject(&MapSet.member?(known, &1))

    question_refs =
      Enum.flat_map(graph["questions"], fn question ->
        [
          "package:" <> question["package"],
          "spec:" <> question["spec"],
          "seam:" <> question["seam"],
          "fixture:" <> question["fixture"]
        ] ++
          if(question["adapter"], do: ["adapter:" <> question["adapter"]], else: [])
      end)
      |> Enum.reject(&MapSet.member?(known, &1))

    case unresolved ++ question_refs do
      [] ->
        :ok

      [id | _] ->
        {:error, reject(:unresolved_id, "graph references an unknown identifier", %{id: id})}
    end
  end

  defp paths(graph, root) do
    referenced =
      Enum.flat_map(graph["specifications"], &List.wrap(&1["executable_evidence"])) ++
        Enum.flat_map(graph["evidence_overlays"], & &1["evidence_sources"]) ++
        Enum.map(graph["adapters"], & &1["path"]) ++
        Enum.map(graph["cookbooks"], & &1["path"]) ++
        Enum.flat_map(graph["fixtures"], &[&1["input_path"], &1["expected_output_path"]])

    missing =
      referenced
      |> Enum.filter(&(&1 not in Enum.map(graph["documents"], fn document -> document["path"] end)))
      |> Enum.find(fn path -> not local_file?(root, path) end)

    case missing do
      nil -> :ok
      path -> {:error, reject(:unresolved_path, "graph references a missing file", %{path: path})}
    end
  end

  defp callbacks(graph) do
    unresolved =
      graph["seams"]
      |> Enum.filter(&(&1["status"] == "implemented"))
      |> Enum.find_value(&unresolved_callback/1)

    case unresolved do
      nil ->
        :ok

      {seam, callback} ->
        {:error,
         reject(:unresolved_callback, "seam callback does not resolve in the loaded cohort", %{
           seam: seam,
           callback: callback
         })}
    end
  end

  defp ownership(graph) do
    seams = Map.new(graph["seams"], &{&1["id"], &1["ownership"]})

    case Enum.find(graph["adapters"], &(Map.get(seams, &1["seam"]) != &1["ownership"])) do
      nil ->
        :ok

      adapter ->
        {:error,
         reject(:undeclared_ownership_change, "adapter ownership differs from its seam", %{
           adapter: adapter["id"],
           seam: adapter["seam"]
         })}
    end
  end

  defp acyclic(scenarios) do
    scenario_graph =
      Map.new(
        scenarios,
        &{"scenario:" <> &1["id"], Enum.map(&1["requires"], fn id -> "scenario:" <> id end)}
      )

    step_graph =
      Enum.flat_map(scenarios, fn scenario ->
        Enum.map(scenario["steps"], fn step ->
          {"step:" <> scenario["id"] <> ":" <> step["id"],
           Enum.map(step["requires"], &("step:" <> scenario["id"] <> ":" <> &1))}
        end)
      end)
      |> Map.new()

    graph = Map.merge(scenario_graph, step_graph)

    visited =
      graph
      |> Map.keys()
      |> Enum.reduce_while({:ok, MapSet.new()}, fn id, {:ok, visited} ->
        continue(visit(id, [], graph, visited))
      end)

    case visited do
      {:ok, _} ->
        :ok

      {:cycle, path} ->
        {:error, reject(:scenario_cycle, "required scenario steps form a cycle", %{path: path})}
    end
  end

  defp visit(id, stack, graph, visited) do
    cond do
      id in stack -> {:cycle, Enum.reverse([id | stack])}
      MapSet.member?(visited, id) -> {:ok, visited}
      true -> visit_children(id, stack, graph, visited)
    end
  end

  defp visit_children(id, stack, graph, visited) do
    children =
      graph
      |> Map.get(id, [])
      |> Enum.reduce_while({:ok, visited}, fn next, {:ok, acc} ->
        continue(visit(next, [id | stack], graph, acc))
      end)

    case children do
      {:ok, acc} -> {:ok, MapSet.put(acc, id)}
      {:cycle, path} -> {:cycle, path}
    end
  end

  defp continue({:ok, acc}), do: {:cont, {:ok, acc}}
  defp continue({:cycle, path}), do: {:halt, {:cycle, path}}

  defp unresolved_callback(seam) do
    case resolve_module(seam["module"]) do
      nil ->
        {seam["id"], seam["module"]}

      module ->
        seam["callbacks"]
        |> Enum.reject(&exported?(module, &1))
        |> List.first()
        |> then(&(&1 && {seam["id"], &1}))
    end
  end

  # Modules are resolved by name against the loaded cohort applications only;
  # no atom is created from graph input.
  defp resolve_module(nil), do: nil

  defp resolve_module(name) when is_binary(name) do
    @apps
    |> Enum.flat_map(&(Application.spec(&1, :modules) || []))
    |> Enum.find(&(inspect(&1) == name))
  end

  defp exported?(module, callback) do
    with [name, arity] <- String.split(callback, "/"),
         {arity, ""} <- Integer.parse(arity),
         true <- Code.ensure_loaded?(module) do
      exports = module.__info__(:functions)

      callbacks =
        if function_exported?(module, :behaviour_info, 1),
          do: module.behaviour_info(:callbacks),
          else: []

      Enum.any?(exports ++ callbacks, fn {fun, fun_arity} ->
        Atom.to_string(fun) == name and fun_arity == arity
      end)
    else
      _ -> false
    end
  end

  defp fixtures(root) do
    loaded =
      root
      |> Path.join("priv/fixtures/*/manifest.json")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.reduce_while({:ok, []}, fn path, {:ok, acc} ->
        case fixture(root, path) do
          {:ok, fixture} -> {:cont, {:ok, [fixture | acc]}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)

    with {:ok, reversed} <- loaded, do: {:ok, Enum.reverse(reversed)}
  end

  defp fixture(root, path) do
    directory = Path.dirname(path)
    relative = Path.relative_to(directory, root)

    with {:ok, manifest} <- read_json(root, Path.relative_to(path, root)),
         :ok <-
           digest_matches(directory, manifest["input"], manifest["input_sha256"], manifest["id"]),
         :ok <-
           digest_matches(
             directory,
             manifest["expected_output"],
             manifest["expected_output_sha256"],
             manifest["id"]
           ) do
      {:ok,
       manifest
       |> Map.put("directory", relative)
       |> Map.put("manifest_path", Path.join(relative, "manifest.json"))
       |> Map.put("input_path", Path.join(relative, manifest["input"]))
       |> Map.put("expected_output_path", Path.join(relative, manifest["expected_output"]))}
    end
  end

  defp digest_matches(directory, file, expected, fixture) when is_binary(file) do
    case File.read(Path.join(directory, file)) do
      {:ok, bytes} ->
        if sha256(bytes) == expected,
          do: :ok,
          else:
            {:error,
             reject(:digest_mismatch, "fixture digest does not match its file", %{
               fixture: fixture,
               file: file
             })}

      {:error, _} ->
        {:error,
         reject(:unresolved_path, "fixture file is missing", %{fixture: fixture, file: file})}
    end
  end

  defp digest_matches(_, _, _, fixture),
    do:
      {:error,
       reject(:unresolved_path, "fixture manifest must name its input and expected output", %{
         fixture: fixture
       })}

  # Package documents are read beside `mix.exs`; documentation is read from
  # the tree `Wotex.Lab.Documentation` locates and named `docs/<kind>/…`.
  defp documents(root, revision) do
    {:ok, docs} = Documentation.directory(root)

    package =
      @document_patterns
      |> Enum.flat_map(&Path.wildcard(Path.join(root, &1)))
      |> Enum.map(&{Path.relative_to(&1, root), &1})

    documentation =
      Documentation.kinds()
      |> Enum.flat_map(&Path.wildcard(Path.join(docs, "#{&1}/*.md")))
      |> Enum.map(&{Path.join("docs", Path.relative_to(&1, docs)), &1})

    documents =
      (package ++ documentation)
      |> Enum.filter(fn {_, file} -> File.regular?(file) end)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn {relative, file} ->
        content = File.read!(file)

        %{
          "id" => "doc:" <> relative,
          "path" => relative,
          "kind" => document_kind(relative),
          "title" => title(content),
          "sha256" => sha256(content),
          "bytes" => byte_size(content),
          "source_url" => source_url(Descriptors.repository(), revision, relative)
        }
      end)

    {:ok, documents}
  end

  # Both `docs/<kind>/` and the monorepo's `docs/packages/<name>/<kind>/`
  # classify the same way.
  defp document_kind(path) do
    case Regex.run(@document_kind, path) do
      [_, "specs"] -> "specification"
      [_, "plans"] -> "completion_plan"
      [_, "decisions"] -> "decision"
      [_, "provenance"] -> "provenance"
      nil -> if String.ends_with?(path, ".livemd"), do: "cookbook", else: "readme"
    end
  end

  defp title(content) do
    case Regex.run(~r/^# (.+)$/m, content) do
      [_, title] -> String.trim(title)
      nil -> "untitled"
    end
  end

  defp node_of(type, map) do
    id =
      case type do
        "package" -> map["id"]
        "specification" -> "spec:" <> map["id"]
        "document" -> map["id"]
        _ -> type <> ":" <> map["id"]
      end

    map
    |> Map.put("id", id)
    |> Map.put("type", type)
  end

  defp node(graph, id) do
    case Enum.find(graph["nodes"], &(&1["id"] == id)) do
      nil -> {:error, reject(:unresolved_id, "answer references an unknown node", %{id: id})}
      node -> {:ok, node}
    end
  end

  defp optional_node(_, _, nil), do: {:ok, nil}
  defp optional_node(graph, prefix, id), do: node(graph, prefix <> id)

  defp status_axes(nil), do: %{}

  defp status_axes(spec),
    do: Map.take(spec, ["implementation_status", "evidence_status", "adoption_status"])

  defp root(root) when is_binary(root) do
    if match?({:ok, _}, Documentation.directory(root)) and
         File.dir?(Path.join(root, "priv/fixtures")),
       do: {:ok, Path.expand(root)},
       else:
         {:error,
          Error.new(
            :invalid_input,
            :construction,
            "root must hold priv/fixtures and a documentation tree"
          )}
  end

  defp root(_),
    do:
      {:error,
       Error.new(
         :invalid_input,
         :construction,
         "root must be a source checkout or unpacked archive"
       )}

  defp catalogue(%{"specifications" => specs} = catalogue) when is_list(specs), do: {:ok, catalogue}

  defp catalogue(_),
    do:
      {:error,
       Error.new(
         :invalid_input,
         :construction,
         "catalogue must be the decoded specification catalogue"
       )}

  defp revision(revision) when is_binary(revision) do
    if Regex.match?(@revision, revision),
      do: {:ok, revision},
      else:
        {:error,
         Error.new(:invalid_input, :construction, "revision must be a 40-hex source revision")}
  end

  defp revision(_),
    do:
      {:error,
       Error.new(:invalid_input, :construction, "revision must be a 40-hex source revision")}

  defp read_json(root, path) do
    with {:ok, content} <- read_file(root, path) do
      content
      |> JSON.decode()
      |> wrap(path)
    end
  end

  defp read_file(root, path) when is_binary(path) do
    case local_file(root, path) do
      {:ok, file} ->
        File.read(file) |> wrap(path)

      :error ->
        {:error,
         reject(:unresolved_path, "input file is missing or outside the root", %{path: path})}
    end
  end

  defp read_file(_, _),
    do: {:error, reject(:unresolved_path, "input path must be a string", %{})}

  defp local_file?(root, path) when is_binary(path), do: match?({:ok, _}, local_file(root, path))
  defp local_file?(_, _), do: false

  defp local_file(root, path) do
    with {:ok, candidate} <- Documentation.resolve(root, path),
         true <- File.regular?(candidate) do
      {:ok, candidate}
    else
      _ -> :error
    end
  end

  defp wrap({:ok, value}, _), do: {:ok, value}

  defp wrap({:error, reason}, path),
    do:
      {:error,
       reject(:unreadable_input, "input cannot be read or decoded", %{
         path: path,
         reason: inspect(reason)
       })}

  defp encode(value) do
    case JSON.encode(value) do
      {:ok, encoded} -> {:ok, encoded <> "\n"}
      {:error, error} -> {:error, Error.new(:encode_failed, :render, error.message)}
    end
  end

  defp source_url(repository, revision, nil), do: repository <> "/tree/" <> revision
  defp source_url(repository, revision, path), do: repository <> "/blob/" <> revision <> "/" <> path

  defp file_sha256(root, path) do
    with {:ok, file} <- local_file(root, path),
         {:ok, content} <- File.read(file) do
      sha256(content)
    else
      _ -> nil
    end
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp reject(code, message, details), do: Error.new(code, :generation, message, details: details)
end
