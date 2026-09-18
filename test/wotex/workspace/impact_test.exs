defmodule Wotex.Workspace.ImpactTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.Impact
  alias Wotex.Workspace.ModuleSpans
  alias WotexWorkspace.Fixtures

  @value """
  defmodule Core.Value do
    @moduledoc false

    def new(x), do: x

    def wrap(x) do
      new(x)
    end
  end
  """

  @client """
  defmodule Runtime.Client do
    @moduledoc false

    defmodule Options do
      @moduledoc false
      def build, do: Core.Value.new(1)
    end

    def call, do: Core.Value.new(2)
  end
  """

  @factory """
  defmodule Http.Factory do
    @moduledoc false
    def value, do: Core.Value.new(3)
  end
  """

  @coap """
  Code.ensure_loaded(Core.Value)

  defmodule Coap do
  end
  """

  # Dexter's answers for the fixture tree, keyed by {module, fun}.
  @references %{
    {"Core.Value", "new"} => [
      %{file: "packages/core/lib/core/value.ex", line: 7},
      %{file: "packages/runtime/lib/runtime/client.ex", line: 6},
      %{file: "packages/runtime/lib/runtime/client.ex", line: 9},
      %{file: "packages/http/test/support/factory.ex", line: 3},
      %{file: "packages/http/test/http/value_test.exs", line: 7},
      %{file: "packages/coap/lib/coap.ex", line: 1},
      %{file: "packages/lab/deps/core/lib/core/value.ex", line: 1},
      %{file: "lib/wotex/workspace.ex", line: 3},
      %{file: "packages/conformance/mix.exs", line: 3}
    ],
    {"Core.Value", nil} => [
      %{file: "packages/core/test/core/value_test.exs", line: 3},
      %{file: "packages/core/test/support/helper.ex", line: 2},
      %{file: "packages/http/test/http/value_test.exs", line: 9}
    ],
    {"Runtime.Client.Options", nil} => [
      %{file: "packages/runtime/test/runtime/options_test.exs", line: 4},
      %{file: "packages/lab/test/lab/client_test.exs", line: 2}
    ],
    {"Http.Factory", nil} => [
      %{file: "packages/http/test/http/value_test.exs", line: 2},
      %{file: "packages/http/test/http/form_test.exs", line: 5},
      %{file: "packages/http/lib/http.ex", line: 12}
    ]
  }

  @definitions %{
    {"Core.Value", "new"} => [%{file: "packages/core/lib/core/value.ex", line: 4}],
    {"Conformance.Runner", nil} => [%{file: "packages/conformance/lib/runner.ex", line: 1}]
  }

  setup context do
    root = Fixtures.tmp_dir(context)
    Fixtures.write!(root, "packages/core/lib/core/value.ex", @value)
    Fixtures.write!(root, "packages/runtime/lib/runtime/client.ex", @client)
    Fixtures.write!(root, "packages/http/test/support/factory.ex", @factory)
    Fixtures.write!(root, "packages/coap/lib/coap.ex", @coap)

    opts = [
      root: root,
      references: fn module, fun -> {:ok, Map.get(@references, {module, fun}, [])} end,
      definitions: fn module, fun -> {:ok, Map.get(@definitions, {module, fun}, [])} end
    ]

    %{opts: opts, manifest: Fixtures.manifest()}
  end

  describe "plan/4" do
    test "selects direct test references and test files one hop away", context do
      assert {:ok, plan} = Impact.plan("Core.Value", "new", context.manifest, context.opts)

      assert plan.target == "Core.Value.new"
      assert plan.hops == ~w(Core.Value Http.Factory Runtime.Client Runtime.Client.Options)
      assert plan.ignored == 3
      assert Enum.map(plan.unresolved, & &1.file) == ["packages/coap/lib/coap.ex"]

      assert plan.packages == [
               %{
                 package: "core",
                 fallback: false,
                 tests: [%{file: "test/core/value_test.exs", via: ["Core.Value"]}]
               },
               %{
                 package: "runtime",
                 fallback: false,
                 tests: [%{file: "test/runtime/options_test.exs", via: ["Runtime.Client.Options"]}]
               },
               %{package: "coap", fallback: true, tests: []},
               %{
                 package: "http",
                 fallback: false,
                 tests: [
                   %{file: "test/http/form_test.exs", via: ["Http.Factory"]},
                   %{
                     file: "test/http/value_test.exs",
                     via: ["direct", "Core.Value", "Http.Factory"]
                   }
                 ]
               },
               %{
                 package: "lab",
                 fallback: false,
                 tests: [%{file: "test/lab/client_test.exs", via: ["Runtime.Client.Options"]}]
               }
             ]
    end

    test "the defining package falls back to stale tests when nothing references it", context do
      assert {:ok, plan} = Impact.plan("Conformance.Runner", nil, context.manifest, context.opts)

      assert plan.references == []
      assert plan.hops == []
      assert plan.packages == [%{package: "conformance", fallback: true, tests: []}]
    end

    test "an unknown target plans nothing", context do
      assert {:ok, plan} = Impact.plan("Nope", nil, context.manifest, context.opts)
      assert plan.packages == []
      assert Impact.render(plan) =~ "no test files reference Nope"
    end

    test "a failing reference source fails the plan", context do
      opts = Keyword.put(context.opts, :references, fn _, _ -> {:error, "boom"} end)
      assert Impact.plan("Core.Value", "new", context.manifest, opts) == {:error, "boom"}

      failing_hop = fn
        "Core.Value", "new" -> {:ok, [%{file: "packages/core/lib/core/value.ex", line: 7}]}
        _, _ -> {:error, "hop failed"}
      end

      opts = Keyword.put(context.opts, :references, failing_hop)
      assert Impact.plan("Core.Value", "new", context.manifest, opts) == {:error, "hop failed"}
    end
  end

  describe "targets/2 and render/1" do
    test "run the selected files per package and mix test --stale on fallback", context do
      {:ok, plan} = Impact.plan("Core.Value", "new", context.manifest, context.opts)
      targets = Impact.targets(plan, context.manifest)

      assert Enum.map(targets, &{&1.package, &1.gate, &1.steps}) == [
               {"core", "files",
                [{"test", ["test", "test/core/value_test.exs"], [mix_env: "test"]}]},
               {"runtime", "files",
                [{"test", ["test", "test/runtime/options_test.exs"], [mix_env: "test"]}]},
               {"coap", "stale", [{"test --stale", ["test", "--stale"], [mix_env: "test"]}]},
               {"http", "files",
                [
                  {"test", ["test", "test/http/form_test.exs", "test/http/value_test.exs"],
                   [mix_env: "test"]}
                ]},
               {"lab", "files", [{"test", ["test", "test/lab/client_test.exs"], [mix_env: "test"]}]}
             ]

      assert Enum.all?(targets, &String.ends_with?(&1.path, "packages/#{&1.package}"))
    end

    test "render/1 lists the files per package with a command line", context do
      {:ok, plan} = Impact.plan("Core.Value", "new", context.manifest, context.opts)
      text = Impact.render(plan)

      assert text =~ "impact of Core.Value.new"
      assert text =~ "references: 4 lib, 1 support, 1 test (3 outside package lib/test ignored)"
      assert text =~ "no enclosing module for packages/coap/lib/coap.ex:1"
      assert text =~ "http (2 test file(s))"
      assert text =~ ~r/test\/http\/value_test\.exs\s+direct, Core\.Value, Http\.Factory/
      assert text =~ "mix pkg http test test/http/form_test.exs test/http/value_test.exs"
      assert text =~ "coap: library references but no referencing test files"
      assert text =~ "mix pkg coap test --stale"
    end
  end

  describe "ModuleSpans" do
    test "finds the innermost module, including nested and __MODULE__ names" do
      source = """
      defmodule Outer do
        def a, do: 1

        defmodule Inner do
          def b, do: 2
        end

        defmodule __MODULE__.Other do
          def c, do: 3
        end

        def d, do: 4
      end

      defmodule Elixir.Top.Level, do: def(e, do: 5)

      defprotocol Proto do
        def f(x)
      end
      """

      assert {:ok, spans} = ModuleSpans.spans(source)

      assert Enum.map(spans, &{&1.module, &1.first, &1.last}) == [
               {"Outer", 1, 13},
               {"Outer.Inner", 4, 6},
               {"Outer.Other", 8, 10},
               {"Top.Level", 15, 15},
               {"Proto", 17, 19}
             ]

      assert ModuleSpans.enclosing(source, 2) == {:ok, "Outer"}
      assert ModuleSpans.enclosing(source, 5) == {:ok, "Outer.Inner"}
      assert ModuleSpans.enclosing(source, 9) == {:ok, "Outer.Other"}
      assert ModuleSpans.enclosing(source, 12) == {:ok, "Outer"}
      assert ModuleSpans.enclosing(source, 15) == {:ok, "Top.Level"}
      assert ModuleSpans.enclosing(source, 18) == {:ok, "Proto"}
      assert ModuleSpans.enclosing(source, 14) == {:ok, nil}
    end

    test "reports a parse failure" do
      assert {:error, message} = ModuleSpans.enclosing("defmodule A do\n", 1, "x.ex")
      assert message =~ "x.ex:"
      assert message =~ "cannot be parsed"
    end
  end
end
