defmodule Wotex.Lab.Bench.Subject do
  @moduledoc false

  # The knowledge graph's subject: this Lab checkout with its documentation
  # tree, read through `Wotex.Lab.Documentation`, at a fixed source revision
  # and generation time, so every iteration generates the same graph.

  alias Wotex.Lab.{Documentation, Graph}

  @revision "0123456789abcdef0123456789abcdef01234567"
  @generated_at ~U[2026-09-18 00:00:00Z]

  @spec input() :: map()
  def input do
    root = Path.expand("../..", __DIR__)
    {:ok, catalogue} = Documentation.resolve(root, "docs/specs/catalogue.yaml")

    options = [
      catalogue: YamlElixir.read_from_file!(catalogue),
      revision: @revision,
      root: root,
      generated_at: @generated_at
    ]

    {:ok, graph} = Graph.generate(options)

    %{
      options: options,
      graph: graph,
      turtle: render(graph, :ecosystem_ttl),
      asyncapi: render(graph, :asyncapi),
      llms: render(graph, :llms),
      answers: answers(graph)
    }
  end

  @spec answers(map()) :: [{:ok, map()}]
  def answers(graph), do: Enum.map(Graph.questions(), &Graph.answer(graph, &1))

  defp render(graph, representation) do
    {:ok, content} = Graph.render(graph, representation)
    content
  end
end
