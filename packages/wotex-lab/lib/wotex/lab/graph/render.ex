defmodule Wotex.Lab.Graph.Render do
  @moduledoc """
  Renders a generated graph into its accepted representations.

  Every renderer is a pure function from the graph map to a binary: JSON
  through `Wotex.JSON` (canonical, sorted keys), JSON-LD 1.1 with an explicit
  `@context`, RDF 1.1 Turtle, a JSON Lines documentation index, `llms.txt`,
  and a small deterministic YAML emitter for the AsyncAPI document. The YAML
  emitter writes only block mappings, block sequences and JSON-quoted
  scalars, which is the subset the Lab needs and the subset the check script
  parses back. `check_turtle/1` is a token-level check of a Turtle document:
  it verifies prefixes, IRIs, literals and statement terminators without
  claiming to be an RDF parser.
  """

  @lab_iri "urn:wotex:lab:graph:"
  @wl "https://wotex.io/lab/graph#"
  @rdfs "http://www.w3.org/2000/01/rdf-schema#"
  @xsd "http://www.w3.org/2001/XMLSchema#"

  @type check_error :: {:undeclared_prefix | :unparsed | :unterminated, String.t()}

  @doc "The `/.well-known/wotex` document."
  @spec well_known(map()) :: map()
  def well_known(graph) do
    package = graph["package"]

    %{
      "schema_version" => graph["schema_version"],
      "kind" => "wotex_lab_well_known",
      "package" =>
        Map.take(package, ["name", "version", "revision", "source_digest", "repository"]),
      "generated_at" => graph["generated_at"],
      "generator" => graph["generator"],
      "representations" => graph["representations"],
      "deployment" => "none",
      "note" =>
        "Accepted endpoint paths of the WLB.07 machine interface; not a running deployment.",
      "status" => Map.get(graph, "lab_status", %{})
    }
  end

  @doc "The JSON-LD 1.1 form of the graph with an explicit `@context`."
  @spec jsonld(map()) :: map()
  def jsonld(graph) do
    nodes =
      Enum.map(graph["nodes"], fn node ->
        node
        |> Map.delete("id")
        |> Map.delete("type")
        |> Enum.map(fn {key, value} -> {"wl:" <> camel(key), literal_ld(value)} end)
        |> Map.new()
        |> Map.put("@id", @lab_iri <> node["id"])
        |> Map.put("@type", "wl:" <> type_name(node["type"]))
        |> Map.merge(edges_ld(graph["edges"], node["id"]))
      end)

    %{
      "@context" => %{
        "@version" => 1.1,
        "wl" => @wl,
        "rdfs" => @rdfs,
        "xsd" => @xsd,
        "label" => "rdfs:label"
      },
      "@id" => @lab_iri <> "manifest",
      "@type" => "wl:Graph",
      "wl:schemaVersion" => graph["schema_version"],
      "wl:generatedAt" => graph["generated_at"],
      "@graph" => nodes
    }
  end

  @doc "The RDF 1.1 Turtle form of the graph."
  @spec turtle(map()) :: binary()
  def turtle(graph) do
    prefixes = [
      "@prefix wl: <#{@wl}> .",
      "@prefix rdfs: <#{@rdfs}> .",
      "@prefix xsd: <#{@xsd}> ."
    ]

    nodes = Enum.map(graph["nodes"], &turtle_node/1)

    edges =
      Enum.map(graph["edges"], fn edge ->
        "<#{@lab_iri}#{edge["from"]}> wl:#{camel(edge["relation"])} <#{@lab_iri}#{edge["to"]}> ."
      end)

    Enum.join(prefixes ++ [""] ++ nodes ++ edges, "\n") <> "\n"
  end

  @doc "The fixture index."
  @spec fixtures_index(map()) :: map()
  def fixtures_index(graph) do
    %{
      "schema_version" => graph["schema_version"],
      "kind" => "wotex_lab_fixture_index",
      "generated_at" => graph["generated_at"],
      "note" => "Expected outputs are separate files that the conformance target never receives.",
      "fixtures" => graph["fixtures"]
    }
  end

  @doc "The documentation index as JSON Lines (one object per line)."
  @spec docs_index(map()) :: binary()
  def docs_index(graph) do
    Enum.map_join(graph["documents"], "\n", fn document ->
      {:ok, line} = Wotex.JSON.encode(document)
      line
    end) <> "\n"
  end

  @doc "The `llms.txt` document."
  @spec llms(map()) :: binary()
  def llms(graph) do
    package = graph["package"]
    status = graph["lab_status"]

    specs =
      graph["specifications"]
      |> Enum.filter(&(&1["package"] == "wotex_lab"))
      |> Enum.map(fn spec ->
        "- [#{spec["id"]}](#{spec["source_url"]}): implementation #{spec["implementation_status"]}, " <>
          "evidence #{spec["evidence_status"]}, adoption #{spec["adoption_status"]}"
      end)

    cookbooks =
      Enum.map(graph["cookbooks"], fn cookbook ->
        "- [#{cookbook["id"]}](#{cookbook["source_url"]}): #{cookbook["title"]} " <>
          "(lane #{cookbook["lane"]}, notebook evidence #{cookbook["evidence"]})"
      end)

    upstream =
      graph["packages"]
      |> Enum.reject(&(&1["name"] == "wotex_lab"))
      |> Enum.map(fn upstream ->
        "- [#{upstream["name"]}](#{upstream["source_url"]}): " <>
          "source snapshot #{upstream["observed_on"]}; Hex #{upstream["artifact"]["hex_observation"]}"
      end)

    questions =
      Enum.map(graph["questions"], fn question ->
        "- #{question["question"]} #{question["statement"]} " <>
          "(package #{question["package"]}, spec #{question["spec"]}, seam #{question["seam"]})"
      end)

    """
    # Wotex Lab

    > An independent WoT consumer laboratory for Elixir, OTP and Nx. Version #{package["version"]} at revision #{package["revision"]}; WLB.07 implementation #{status["implementation_status"]}, evidence #{status["evidence_status"]}, adoption #{status["adoption_status"]}. No wotex package is published on Hex at this revision; the graph is a source snapshot with content digests, not a deployment.

    Statuses in this file are copied verbatim from the catalogues. Upstream evidence and adoption axes absent in source are `not_reported`, never inferred.

    ## Specifications

    #{Enum.join(specs, "\n")}

    ## Cookbooks

    #{Enum.join(cookbooks, "\n")}

    ## Ownership

    #{Enum.join(questions, "\n")}

    ## Upstream source snapshots

    #{Enum.join(upstream, "\n")}

    ## Optional

    - [Completion contract](#{document_url(graph, package["completion_plan"])}): accepted work packages, not an execution tracker
    - [Historical source baseline](#{package["source_url"]}/priv/provenance/source-index.json): immutable inspected revisions and their then-observed catalogue statuses
    """
  end

  defp document_url(graph, path) do
    case Enum.find(graph["documents"] || [], &(&1["path"] == path)) do
      %{"source_url" => url} -> url
      nil -> graph["package"]["source_url"]
    end
  end

  @doc "Encodes JSON-compatible data as deterministic block YAML."
  @spec yaml(term()) :: binary()
  def yaml(value), do: yaml(value, 0) <> "\n"

  @doc "Checks a Turtle document at the token level: prefixes, IRIs, literals and terminators."
  @spec check_turtle(binary()) :: :ok | {:error, check_error()}
  def check_turtle(document) when is_binary(document) do
    prefixes =
      ~r/^@prefix ([A-Za-z][\w-]*): <[^\s<>"{}|^`\\]*> \.$/m
      |> Regex.scan(document)
      |> Enum.map(&Enum.at(&1, 1))

    body = Regex.replace(~r/^@prefix .*$/m, document, "")

    tokens =
      Regex.scan(
        ~r/<[^\s<>"{}|^`\\]*>|"(?:[^"\\]|\\.)*"|[A-Za-z][\w-]*:[\w.-]*|\btrue\b|\bfalse\b|\ba\b|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|[;,.]|\S+/,
        body
      )
      |> List.flatten()

    case check_tokens(tokens, prefixes) do
      :ok -> check_terminators(body)
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_tokens(tokens, prefixes) do
    Enum.reduce_while(tokens, :ok, fn token, :ok ->
      cond do
        String.starts_with?(token, "<") or String.starts_with?(token, "\"") -> {:cont, :ok}
        token in ["a", "true", "false", ";", ",", "."] -> {:cont, :ok}
        Regex.match?(~r/\A-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\z/, token) -> {:cont, :ok}
        prefixed?(token, prefixes) -> {:cont, :ok}
        Regex.match?(~r/\A[A-Za-z][\w-]*:/, token) -> {:halt, {:error, {:undeclared_prefix, token}}}
        true -> {:halt, {:error, {:unparsed, token}}}
      end
    end)
  end

  defp prefixed?(token, prefixes) do
    case String.split(token, ":", parts: 2) do
      [prefix, _] -> prefix in prefixes
      _ -> false
    end
  end

  # Every non-blank line closes a statement (` .`) or continues one (` ;`, ` ,`),
  # and the document ends with a closed statement.
  defp check_terminators(body) do
    lines =
      body
      |> String.split("\n")
      |> Enum.map(&String.trim_trailing/1)
      |> Enum.reject(&(String.trim(&1) == ""))

    open = Enum.find(lines, fn line -> not String.ends_with?(line, [" .", " ;", " ,"]) end)
    last = List.last(lines)

    cond do
      open != nil -> {:error, {:unterminated, String.slice(open, 0, 80)}}
      last != nil and not String.ends_with?(last, " .") -> {:error, {:unterminated, last}}
      true -> :ok
    end
  end

  defp turtle_node(node) do
    subject = "<#{@lab_iri}#{node["id"]}>"

    properties =
      node
      |> Map.drop(["id", "type"])
      |> Enum.sort()
      |> Enum.flat_map(fn {key, value} -> turtle_property(key, value) end)

    lines = ["#{subject} a wl:#{type_name(node["type"])} ;" | properties]

    String.replace_suffix(Enum.join(lines, "\n"), " ;", "") <> " .\n"
  end

  defp turtle_property(key, value) when is_list(value) do
    value
    |> Enum.filter(&scalar?/1)
    |> Enum.map(&"    wl:#{camel(key)} #{turtle_literal(&1)} ;")
  end

  defp turtle_property(key, value) when is_map(value) do
    value
    |> Enum.sort()
    |> Enum.filter(fn {_, nested_value} -> scalar?(nested_value) end)
    |> Enum.map(fn {nested, nested_value} ->
      "    wl:#{camel(key)}_#{camel(nested)} #{turtle_literal(nested_value)} ;"
    end)
  end

  defp turtle_property(_, nil), do: []
  defp turtle_property(key, value), do: ["    wl:#{camel(key)} #{turtle_literal(value)} ;"]

  defp turtle_literal(value) when is_boolean(value), do: to_string(value)
  defp turtle_literal(value) when is_number(value), do: to_string(value)

  defp turtle_literal(value) when is_binary(value) do
    {:ok, encoded} = Wotex.JSON.encode(value)
    encoded
  end

  defp scalar?(value), do: is_binary(value) or is_number(value) or is_boolean(value)

  defp edges_ld(edges, id) do
    edges
    |> Enum.filter(&(&1["from"] == id))
    |> Enum.group_by(& &1["relation"], &%{"@id" => @lab_iri <> &1["to"]})
    |> Map.new(fn {relation, targets} -> {"wl:" <> camel(relation), targets} end)
  end

  defp literal_ld(value) when is_map(value),
    do: Map.new(value, fn {key, nested} -> {"wl:" <> camel(key), literal_ld(nested)} end)

  defp literal_ld(value) when is_list(value), do: Enum.map(value, &literal_ld/1)
  defp literal_ld(value), do: value

  defp type_name(type) do
    type
    |> String.split(~r/[_-]/)
    |> Enum.map_join(&String.capitalize/1)
  end

  defp camel(key) do
    key = to_string(key)

    case String.split(key, ~r/[_-]/) do
      [head | tail] -> head <> Enum.map_join(tail, &String.capitalize/1)
      [] -> key
    end
  end

  defp yaml(value, indent) when is_map(value) and map_size(value) == 0 and indent >= 0, do: "{}"
  defp yaml([], _), do: "[]"

  defp yaml(value, indent) when is_map(value) do
    value
    |> Enum.sort()
    |> Enum.map_join("\n", fn {key, nested} ->
      pad(indent) <> yaml_scalar(to_string(key)) <> ":" <> yaml_nested(nested, indent)
    end)
  end

  defp yaml(value, indent) when is_list(value) do
    Enum.map_join(value, "\n", fn item -> pad(indent) <> "-" <> yaml_nested(item, indent) end)
  end

  defp yaml(value, _), do: yaml_scalar(value)

  defp yaml_nested(value, indent)
       when (is_map(value) and map_size(value) > 0) or (is_list(value) and value != []),
       do: "\n" <> yaml(value, indent + 2)

  defp yaml_nested(value, indent), do: " " <> yaml(value, indent)

  defp yaml_scalar(nil), do: "null"
  defp yaml_scalar(value) when is_boolean(value) or is_number(value), do: to_string(value)

  defp yaml_scalar(value) when is_binary(value) do
    {:ok, encoded} = Wotex.JSON.encode(value)
    encoded
  end

  defp pad(indent), do: String.duplicate(" ", indent)
end
