# Generates the WLB.07 knowledge graph into a temporary directory and validates
# every representation. Runs through Mix so the YAML dependency is available:
# `mix run --no-start bin/check_graph.exs`. No network access; the source
# revision comes from the local checkout and is only used to build URLs.

defmodule Wotex.Lab.Check.Graph do
  @moduledoc false

  alias Wotex.Lab.Graph
  alias Wotex.Lab.Graph.{Interfaces, Render}

  def run do
    root = Path.expand("..", __DIR__)
    File.cd!(root)
    catalogue = YamlElixir.read_from_file!("docs/specs/catalogue.yaml")
    revision = revision!(root)

    graph =
      case Graph.generate(catalogue: catalogue, revision: revision, root: root) do
        {:ok, graph} -> graph
        {:error, error} -> abort("graph generation rejected the inputs: " <> inspect(error))
      end

    directory = Path.join(root, ".graph-check.#{System.unique_integer([:positive])}")

    try do
      files =
        case Graph.write(graph, directory) do
          {:ok, files} -> files
          {:error, error} -> abort("graph rendering failed: " <> inspect(error))
        end

      Enum.each(Graph.representations(), fn {key, path} ->
        file = Path.join(directory, String.trim_leading(path, "/"))
        File.regular?(file) || abort("representation missing: #{path}")
        validate(key, File.read!(file), graph)
      end)

      Enum.each(Graph.questions(), fn question ->
        case Graph.answer(graph, question) do
          {:ok, answer} ->
            Enum.each(~w(package spec seam ownership canonical_source fixture status), fn key ->
              is_nil(answer[key]) && abort("ownership answer #{question} lacks #{key}")
            end)

          {:error, error} ->
            abort("ownership question #{question} unresolved: " <> inspect(error))
        end
      end)

      IO.puts(
        "graph: #{length(graph["nodes"])} nodes, #{length(graph["edges"])} edges, " <>
          "#{length(files)} representations validated; source snapshot, optional host contract"
      )
    after
      File.rm_rf(directory)
    end
  end

  defp validate(key, content, graph) when key in [:well_known, :manifest, :fixtures_index] do
    decoded = json!(content, key)
    decoded["schema_version"] == graph["schema_version"] || abort("#{key} schema version drift")
    decoded["kind"] || abort("#{key} lacks a kind")
  end

  defp validate(:manifest_jsonld, content, _graph) do
    decoded = json!(content, :manifest_jsonld)
    context = decoded["@context"]
    (is_map(context) and context["@version"] == 1.1) || abort("jsonld must declare a 1.1 @context")
    is_list(decoded["@graph"]) || abort("jsonld lacks @graph")
  end

  defp validate(:ecosystem_ttl, content, _graph) do
    case Render.check_turtle(content) do
      :ok -> :ok
      {:error, reason} -> abort("turtle check failed: " <> inspect(reason))
    end
  end

  defp validate(:docs_index, content, graph) do
    lines = content |> String.split("\n", trim: true)
    length(lines) == length(graph["documents"]) || abort("docs index line count drift")
    Enum.each(lines, &json!(&1, :docs_index))
  end

  defp validate(:openapi, content, _graph) do
    decoded = json!(content, :openapi)
    decoded["openapi"] == Interfaces.openapi_version() || abort("openapi dialect drift")
    decoded["openapi"] == "3.2.0" || abort("openapi must declare 3.2.0")

    decoded["x-wotex-deployment"] == "optional-workbench-host" ||
      abort("openapi must name only the optional workbench host")

    decoded["servers"] == [%{"description" => "Workbench host", "url" => "/api/v1"}] ||
      abort("openapi server path drift")

    Map.has_key?(decoded["paths"], "/scenarios") || abort("openapi lacks /scenarios")
  end

  defp validate(:asyncapi, content, graph) do
    decoded = YamlElixir.read_from_string!(content)
    decoded == Interfaces.asyncapi(graph) || abort("asyncapi yaml does not round-trip")
    decoded["asyncapi"] == Interfaces.asyncapi_version() || abort("asyncapi dialect drift")
    decoded["asyncapi"] == "3.1.0" || abort("asyncapi must declare 3.1.0")
  end

  defp validate(:llms, content, graph) do
    String.starts_with?(content, "# Wotex Lab\n") || abort("llms.txt must start with the title")

    Enum.each(
      graph["cookbooks"],
      &(String.contains?(content, &1["id"]) || abort("llms lacks a cookbook"))
    )
  end

  defp json!(content, key) do
    case Wotex.JSON.decode(content) do
      {:ok, decoded} -> decoded
      {:error, error} -> abort("#{key} is not valid JSON: " <> inspect(error))
    end
  end

  defp revision!(root) do
    case System.cmd("git", ["-C", root, "rev-parse", "HEAD"], stderr_to_stdout: true) do
      {output, 0} ->
        revision = String.trim(output)
        Regex.match?(~r/\A[0-9a-f]{40}\z/, revision) || abort("unusable source revision")
        revision

      {_output, _status} ->
        abort("the graph check needs the local source revision; run it inside the checkout")
    end
  rescue
    ErlangError ->
      abort("the graph check needs the local source revision; run it inside the checkout")
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Lab.Check.Graph.run()
