Code.require_file("support/subject.exs", __DIR__)

alias Wotex.Lab.Bench.Subject
alias Wotex.Lab.Graph

subject = Subject.input()
nodes = length(subject.graph["nodes"])
edges = length(subject.graph["edges"])
questions = length(subject.answers)

Benchee.run(
  %{
    "generate" => fn %{options: options, graph: graph} ->
      {:ok, ^graph} = Graph.generate(options)
    end,
    "render ecosystem.ttl (Turtle)" => fn %{graph: graph, turtle: turtle} ->
      {:ok, ^turtle} = Graph.render(graph, :ecosystem_ttl)
    end,
    "render asyncapi.yaml" => fn %{graph: graph, asyncapi: asyncapi} ->
      {:ok, ^asyncapi} = Graph.render(graph, :asyncapi)
    end,
    "render llms.txt" => fn %{graph: graph, llms: llms} ->
      {:ok, ^llms} = Graph.render(graph, :llms)
    end,
    "answer every ownership question" => fn %{graph: graph, answers: answers} ->
      ^answers = Subject.answers(graph)
    end
  },
  inputs: %{"wotex-lab checkout" => subject},
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/knowledge_graph.md",
     title: "# Knowledge graph generation and representations",
     description: """
     `Wotex.Lab.Graph` over its real subject: this Lab checkout with the
     documentation tree `Wotex.Lab.Documentation` locates, the specification
     catalogue decoded before the run, a fixed source revision and a fixed
     generation time. For this run the graph has #{nodes} nodes and #{edges}
     edges. The subject changes with the repository, so results from
     different commits are not directly comparable.

     `generate` is `Wotex.Lab.Graph.generate/1`: reading the source index and
     source cohort (decoded with `Wotex.JSON.decode/2`), the completion plan,
     the fixture manifests with a check of each fixture's input and expected
     output digests, the README, the cookbook notebooks and every
     documentation page; digesting the package source tree (`lib`, `priv`,
     `mix.exs`, `README.md`, `CHANGELOG.md`); and joining them with the
     cookbook catalogue and the scenario, adapter and seam descriptors into
     one validated graph. `render ecosystem.ttl (Turtle)`,
     `render asyncapi.yaml` and `render llms.txt` are
     `Wotex.Lab.Graph.render/2` for the representations the Lab serializes
     itself: RDF 1.1 Turtle, the AsyncAPI document through the block YAML
     emitter, and `llms.txt`. Turtle and YAML quote string literals with
     `Wotex.JSON.encode/1`. The representations that are a projection passed
     whole to `Wotex.JSON.encode/1` are left out.
     `answer every ownership question` is `Wotex.Lab.Graph.answer/2` for each
     of the #{questions} ownership questions. Every job compares its
     result with the value computed before the run.
     """}
  ]
)
