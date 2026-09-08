defmodule Wotex.Lab.Check.OCISource do
  @moduledoc false

  @required [
    "@sha256:290e52da1c5d5cbf62344d384387e8bdfa7d8a64784302bb7770e76ad13c88a5",
    "FROM ${ELIXIR_IMAGE} AS build",
    "FROM ${ELIXIR_IMAGE} AS runtime",
    "mix deps.get --only prod",
    "mix compile --warnings-as-errors && mix release",
    "USER 65532:65532",
    "VOLUME [\"/var/lib/wotex-lab\"]",
    "HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3",
    "WotexLabWorkbench.Health.probe()",
    "ENTRYPOINT [\"/opt/wotex/bin/wotex_lab_workbench\"]",
    "CMD [\"start\"]"
  ]
  @forbidden ["WOTEX_PATH_DEPS", "git clone", "ADD http", "curl |", "wget |", "USER root"]

  def run do
    root = Path.expand("..", __DIR__)
    dockerfile = Path.join(root, "hosts/workbench/Dockerfile")
    ignore = Path.join(root, "hosts/workbench/.dockerignore")
    source = File.read!(dockerfile)

    Enum.each(@required, &(String.contains?(source, &1) || abort("Dockerfile lacks #{&1}")))
    Enum.each(@forbidden, &(!String.contains?(source, &1) || abort("Dockerfile contains #{&1}")))

    ignored = ignore |> File.read!() |> String.split("\n", trim: true) |> MapSet.new()

    Enum.each(
      ~w(_build deps doc test .git),
      &(MapSet.member?(ignored, &1) || abort(".dockerignore lacks #{&1}"))
    )

    if System.get_env("WOTEX_LAB_OCI_CHECK") == "1" do
      case System.cmd("docker", ["build", "--check", "-f", dockerfile, Path.dirname(dockerfile)],
             stderr_to_stdout: true
           ) do
        {output, 0} -> IO.write(output)
        {output, _status} -> abort("docker build check failed:\n" <> output)
      end
    end

    IO.puts("OCI source: pinned base, non-root runtime, health probe and ephemeral volume declared")
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Lab.Check.OCISource.run()
