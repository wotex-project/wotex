defmodule Wotex.Lab.Bench.Records do
  @moduledoc false

  # Evidence records whose fixture digests, input references and assertions
  # grow together. The fixtures are written to a temporary tree of lane
  # directories, the layout of `priv/fixtures`, and each record carries the
  # digests of exactly those files. The eight WoTEx packages are workspace
  # dependencies without archive evidence; the Hex packages carry a digest.

  alias Wotex.Lab.Evidence.{Digest, Record}
  alias Wotex.Lab.Runner.Budgets

  @lanes ~w(continuum directory http loopback metrics mqtt thermal)
  @statuses [:pass, :pass, :pass, :fail, :unsupported, :not_run]
  @readings 400
  @workspace ~w(wotex wotex_nx wotex_runtime wotex_directory wotex_binding_http
                wotex_binding_mqtt wotex_continuum wotex_conformance)
  @hex [
    {"axon", "0.8.1"},
    {"bandit", "1.12.5"},
    {"complex", "0.7.0"},
    {"emqtt", "1.16.0"},
    {"ex_maude", "0.4.1"},
    {"exla", "0.13.1"},
    {"explorer", "0.12.0"},
    {"exqlite", "0.40.0"},
    {"finch", "0.23.0"},
    {"jason", "1.4.5"},
    {"mint", "1.10.0"},
    {"nimble_options", "1.1.1"},
    {"nx", "0.13.1"},
    {"plug", "1.20.3"},
    {"req", "0.7.4"},
    {"telemetry", "1.4.2"}
  ]

  @spec sizes() :: %{String.t() => pos_integer()}
  def sizes, do: %{"8 fixtures" => 8, "128 fixtures" => 128, "1024 fixtures" => 1_024}

  @spec root() :: Path.t()
  def root, do: Path.join(System.tmp_dir!(), "wotex-lab-bench-evidence")

  @spec input(pos_integer()) :: map()
  def input(count) do
    tree = Path.join(root(), Integer.to_string(count))
    File.rm_rf!(tree)
    names = Enum.map(1..count, &write_fixture(tree, &1))
    fixtures = Map.new(names, &{&1, Digest.file!(Path.join(tree, &1))})
    fields = fields(count, names, fixtures)
    {:ok, record} = Record.new(fields)
    map = Record.to_map(record)
    {:ok, ^record} = Record.from_map(map)
    {:ok, digest} = Record.digest(record)
    {:ok, tree_digest} = Digest.tree(tree, ["**/*.json"])

    %{
      fields: fields,
      record: record,
      map: map,
      digest: digest,
      tree: tree,
      tree_digest: tree_digest
    }
  end

  defp write_fixture(tree, index) do
    lane = Enum.at(@lanes, rem(index, length(@lanes)))
    name = Path.join(lane, "fixture-#{String.pad_leading(Integer.to_string(index), 4, "0")}.json")
    path = Path.join(tree, name)
    readings = Enum.map_join(1..@readings, ",", &Float.to_string(15.0 + rem(&1 * index, 97) / 10))
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, ~s({"lane":"#{lane}","index":#{index},"readings":[#{readings}]}\n))
    name
  end

  defp fields(count, names, fixtures) do
    %{
      scenario_id: "smart-room",
      revision: "0123456789abcdef0123456789abcdef01234567",
      attempt: 1,
      source_tree_digest: Digest.bytes("source tree"),
      lock_digest: Digest.bytes("mix.lock"),
      dependencies: dependencies(),
      fixtures: fixtures,
      seed: 42,
      toolchain: Digest.toolchain(Nx.BinaryBackend),
      budgets: Budgets.defaults(),
      inputs: Enum.map(names, &("fixture:" <> &1)),
      assertions: Enum.map(1..count, &assertion/1),
      outcomes: %{effect: 22.5, decision: "dispatched", checked: count, under_budget: true},
      durations: %{preflight_ms: 3, run_ms: 1_250, cleanup_ms: 12},
      cleanup: %{status: :ok, details: %{"children" => 0, "work_directory" => "removed"}}
    }
  end

  defp dependencies do
    Enum.map(@workspace, &%{name: &1, version: "0.1.0", archive: :missing}) ++
      Enum.map(@hex, fn {name, version} ->
        %{name: name, version: version, archive: Digest.bytes(name <> "-" <> version <> ".tar")}
      end)
  end

  defp assertion(index) do
    %{id: "check-#{index}", status: Enum.at(@statuses, rem(index, length(@statuses)))}
  end
end
