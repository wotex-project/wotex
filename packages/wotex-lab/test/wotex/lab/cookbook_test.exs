defmodule Wotex.Lab.CookbookTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.{Cookbook, Documentation}
  alias Wotex.Lab.Test.{CookbookRunner, MqttBroker}

  @moduletag :integration
  @moduletag capture_log: true

  @root Path.expand("../../..", __DIR__)
  {:ok, docs} = Documentation.directory(@root)
  @docs docs
  @fault_checks ["connect-reported", "oversized-dropped", "transport-down"]
  @http_notebooks ~w(consume-http write-and-act observe-sse smart-room)

  setup_all do
    catalogue = YamlElixir.read_from_file!(Path.join(@docs, "specs/catalogue.yaml"))

    source =
      @root
      |> Path.join(catalogue["source_index"])
      |> File.read!()
      |> JSON.decode!()

    specs = catalogue["specifications"]

    completion_ids =
      specs
      |> Enum.flat_map(& &1["completion_items"])
      |> Enum.uniq()

    %{
      spec_ids: Enum.map(specs, & &1["id"]),
      completion_ids: completion_ids,
      upstream_ids: Enum.flat_map(source["packages"], & &1["completion_ids"])
    }
  end

  for entry <- Cookbook.list() do
    @entry entry

    test "#{entry.id} has every section, resolves its ids and runs against the cohort", context do
      entry = @entry
      {:ok, source} = Cookbook.read(entry.id)

      assert Cookbook.missing_sections(source) == []

      assert Cookbook.headings(source) --
               (Cookbook.headings(source) -- Cookbook.required_sections()) ==
               Cookbook.required_sections()

      [install | _] = Cookbook.cells(source)
      assert CookbookRunner.install_cell?(install)
      assert install =~ ~s({:wotex_lab, "~> 0.1.0"})
      refute install =~ "git:"
      refute install =~ "github:"
      refute install =~ "path:"
      assert source =~ "none of the `wotex*` packages is published on Hex"
      assert source =~ "source-cohort.json"

      assert_honest(source, entry.evidence)
      assert entry.specs -- context.spec_ids == []
      assert entry.completion_ids -- context.completion_ids == []
      assert entry.upstream -- context.upstream_ids == []

      for id <- entry.specs, do: assert(source =~ id)
      for id <- entry.completion_ids, do: assert(source =~ id)

      assert {:ok, outcome} = CookbookRunner.run(entry.id)
      assert outcome.leaked == 0
      assert outcome.reclaimed == %{processes: 0, handlers: 0}
      assert outcome.cells > 3
      assert_checks(outcome.result, entry.checks)

      for module <- outcome.modules do
        assert Code.ensure_loaded?(module), "#{entry.id} references unloaded #{inspect(module)}"
      end
    end
  end

  for id <- @http_notebooks do
    @http_notebook id

    test "#{id} uses per-run function plugs during overlapping evaluations" do
      id = @http_notebook
      {:ok, entry} = Cookbook.fetch(id)
      {:ok, source} = Cookbook.read(id)

      for cell <- Cookbook.cells(source) do
        {_, definitions} =
          cell
          |> Code.string_to_quoted!()
          |> Macro.prewalk([], fn
            {:defmodule, _, _} = node, acc -> {node, [node | acc]}
            node, acc -> {node, acc}
          end)

        assert definitions == [], "HTTP cookbook helpers must not compile shared modules"
      end

      outcomes =
        [1, 2]
        |> Task.async_stream(fn _ -> CookbookRunner.run(id) end,
          max_concurrency: 2,
          timeout: entry.timeout_ms + 5_000
        )
        |> Enum.map(fn {:ok, {:ok, outcome}} -> outcome end)

      assert length(outcomes) == 2

      for outcome <- outcomes do
        assert outcome.leaked == 0
        assert outcome.reclaimed == %{processes: 0, handlers: 0}
        assert is_function(Keyword.fetch!(outcome.binding, :http_handler), 2)
        assert_checks(outcome.result, entry.checks)
      end

      [first, second] = Enum.map(outcomes, &Keyword.fetch!(&1.binding, :server))
      refute first == second
      refute Process.alive?(first)
      refute Process.alive?(second)
    end
  end

  test "caller bindings do not authorize process shutdown or directory deletion" do
    suffix = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    dir = Path.join(System.tmp_dir!(), "wotex-cookbook-caller-#{suffix}")
    File.mkdir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    File.chmod!(dir, 0o700)
    supervisor = start_supervised!(Task.Supervisor)
    path = Path.join(dir, "caller-owned.txt")
    File.write!(path, "caller data")

    assert {:ok, outcome} =
             CookbookRunner.run("parse-td", binding: [lab: supervisor, tmp_dir: dir])

    assert outcome.leaked == 0
    assert outcome.reclaimed == %{processes: 0, handlers: 0}
    assert Process.alive?(supervisor)
    assert File.read!(path) == "caller data"
  end

  describe "against a disposable broker" do
    @describetag :broker
    @describetag timeout: 120_000

    setup do
      %{broker: MqttBroker.start()}
    end

    test "consume-mqtt runs its non-fault cells against eclipse-mosquitto", %{broker: broker} do
      {:ok, entry} = Cookbook.fetch("consume-mqtt")

      assert {:ok, outcome} =
               CookbookRunner.run("consume-mqtt", binding: [broker_href: MqttBroker.href(broker)])

      assert outcome.leaked == 0
      assert outcome.reclaimed == %{processes: 0, handlers: 0}
      assert_checks(outcome.result, entry.checks -- @fault_checks)
    end

    test "smart-room reads its meter from eclipse-mosquitto", %{broker: broker} do
      {:ok, entry} = Cookbook.fetch("smart-room")

      assert {:ok, outcome} =
               CookbookRunner.run("smart-room", binding: [broker_href: MqttBroker.href(broker)])

      assert outcome.leaked == 0
      assert outcome.reclaimed == %{processes: 0, handlers: 0}
      assert_checks(outcome.result, entry.checks)
    end
  end

  # A partial notebook must say so and mark its documentation-only code; an
  # executable one must carry no documentation-only code block.
  defp assert_honest(source, :partial) do
    assert source =~ "```text"
    assert source =~ "# Planned ("
    assert source =~ "documentation only"
  end

  defp assert_honest(source, :executable), do: refute(source =~ "```text")

  defp assert_checks(result, checks) do
    assert is_map(result), "the last cell must return the checks map"
    assert Enum.sort(Map.keys(result)) == Enum.sort(checks)
    failed = for {check, value} <- result, value != true, do: check
    assert failed == [], "checks not satisfied: #{inspect(failed)}"
  end
end
