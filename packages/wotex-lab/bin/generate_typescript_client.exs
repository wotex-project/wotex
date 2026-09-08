Code.require_file("support/typescript_client.exs", __DIR__)

alias Wotex.Lab.Check.TypeScriptClient
alias Wotex.Lab.Graph
alias Wotex.Lab.Graph.Interfaces

root = Path.expand("..", __DIR__)
target = Path.join(root, "clients/typescript")
catalogue = YamlElixir.read_from_file!(Path.join(root, "docs/specs/catalogue.yaml"))
{revision, 0} = System.cmd("git", ["-C", root, "rev-parse", "HEAD"], stderr_to_stdout: true)
{:ok, graph} = Graph.generate(catalogue: catalogue, revision: String.trim(revision), root: root)
files = TypeScriptClient.render(Interfaces.openapi(graph), File.read!(Path.join(root, "LICENSE")))

case System.argv() do
  ["--write"] ->
    Enum.each(files, fn {relative, content} ->
      path = Path.join(target, relative)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
    end)

    IO.puts("generated @wotex/lab-client #{graph["package"]["version"]}")

  ["--check"] ->
    Enum.each(files, fn {relative, expected} ->
      path = Path.join(target, relative)
      File.read(path) == {:ok, expected} || raise "generated client drift: #{relative}"
    end)

    {_, 0} = System.cmd("node", ["--test"], cd: target, into: IO.stream())

    {pack, 0} =
      System.cmd("npm", ["pack", "--dry-run", "--json"], cd: target, stderr_to_stdout: true)

    [%{"files" => packed}] = Jason.decode!(pack)
    names = MapSet.new(packed, & &1["path"])

    Enum.each(~w(package.json README.md LICENSE dist/index.js dist/index.d.ts), fn required ->
      MapSet.member?(names, required) || raise "npm archive lacks #{required}"
    end)

    IO.puts("typescript client: generated sources, node tests and npm archive pass")

  _other ->
    raise "usage: mix run --no-start bin/generate_typescript_client.exs --check|--write"
end
