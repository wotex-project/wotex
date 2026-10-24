defmodule Mix.Tasks.WotexLab.Seed do
  @shortdoc "Generates backend reference-room and island seed data"

  @moduledoc """
  Generates deterministic seed JSON from the host's trusted `priv/seeds.exs`.

      mix seed
      mix seed --check

  The task starts no application, room, device, model or database. Repeated runs
  produce identical bytes. `--check` refuses missing or stale outputs without
  changing them. `--output` selects a destination directory for an isolated build.
  The Workbench and its development Storybook route share the generated island
  catalogue directly; production islands never import these Storybook payloads.
  """

  use Mix.Task

  alias Wotex.Lab.Island.Encoder
  alias WotexLabWorkbench.Seeds

  @impl Mix.Task
  def run(arguments) do
    {opts, rest, invalid} =
      OptionParser.parse(arguments, strict: [check: :boolean, output: :string])

    if rest != [] or invalid != [],
      do: Mix.raise("expected mix seed [--check] [--output directory]")

    Mix.Task.run("compile")
    root = Path.dirname(Mix.Project.project_file())
    {data, _} = Code.eval_file(Path.join(root, "priv/seeds.exs"))
    validate!(data)
    destination = Path.expand(Keyword.get(opts, :output, Path.join(root, "priv/seeds")))

    Enum.each(~w(room islands components), fn name ->
      bytes = Jason.encode!(Map.fetch!(data, name), pretty: true) <> "\n"
      output!(destination, name, bytes, opts[:check])
    end)

    Mix.shell().info(
      "seed: reference room and island stories #{if opts[:check], do: "verified", else: "generated"}"
    )
  end

  defp output!(destination, name, bytes, true) do
    path = Path.join(destination, name <> ".json")
    if File.read(path) != {:ok, bytes}, do: Mix.raise("stale seed data: run mix seed (#{path})")
  end

  defp output!(destination, name, bytes, _) do
    File.mkdir_p!(destination)
    File.write!(Path.join(destination, name <> ".json"), bytes)
  end

  defp validate!(%{"room" => room, "islands" => islands, "components" => components} = data)
       when map_size(data) == 3 and is_map(components) and map_size(components) > 0 do
    case Seeds.admit_room(room) do
      {:ok, _} -> :ok
      {:error, _} -> Mix.raise("invalid reference-room seed definition")
    end

    expected = Enum.sort(~w(canvas chart data-grid tabs))
    if Enum.sort(Map.keys(islands)) != expected, do: Mix.raise("invalid island seed catalogue")

    Enum.each(islands, fn {component, states} ->
      Enum.each(states, fn {state, payload} ->
        case Encoder.encode(component, payload) do
          {:ok, _} -> :ok
          {:error, reason} -> Mix.raise("invalid #{component}/#{state} seed: #{inspect(reason)}")
        end
      end)
    end)
  end

  defp validate!(_), do: Mix.raise("invalid seed definition")
end
