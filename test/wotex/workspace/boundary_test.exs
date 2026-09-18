defmodule Wotex.Workspace.BoundaryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.Boundary
  alias Wotex.Workspace.Boundary.Index
  alias WotexWorkspace.Fixtures

  # A sibling index: Sib.Hidden is `@moduledoc false`, Sib.Public exposes
  # `open/1` and hides `secret/1`.
  defp index do
    %Index{}
    |> Boundary.add({"Sib.Hidden", true, [{:anything, 0}]})
    |> Boundary.add({"Sib.Public", false, [{:secret, 1}]})
    |> Boundary.add({"Sib.Public.Nested", false, []})
  end

  defp messages(source) do
    source
    |> Boundary.analyze("packages/x/lib/x.ex", index())
    |> Enum.map(&Boundary.format/1)
  end

  describe "analyze/3" do
    test "resolves plain aliases, as: aliases and multi-aliases" do
      source = """
      defmodule Consumer do
        alias Sib.Public
        alias Sib.Hidden, as: H
        alias Sib.{Hidden, Public.Nested}

        def a, do: Public.secret(1)
        def b, do: Public.open(1)
        def c, do: H.anything()
        def d, do: Hidden.other(1, 2)
        def e, do: Nested.fine()
      end
      """

      assert messages(source) == [
               "packages/x/lib/x.ex:3: Sib.Hidden is not public API",
               "packages/x/lib/x.ex:4: Sib.Hidden is not public API",
               "packages/x/lib/x.ex:6: Sib.Public.secret/1 is not public API",
               "packages/x/lib/x.ex:8: Sib.Hidden.anything/0 is not public API",
               "packages/x/lib/x.ex:9: Sib.Hidden.other/2 is not public API"
             ]
    end

    test "reports captures, module references and struct literals" do
      source = """
      defmodule Consumer do
        def a, do: &Sib.Public.secret/1
        def b, do: &Sib.Public.open/1
        def c, do: Sib.Hidden
        def d, do: %Sib.Hidden{}
        def e, do: Sib.Public.Nested
        @behaviour Sib.Hidden
      end
      """

      assert messages(source) == [
               "packages/x/lib/x.ex:2: Sib.Public.secret/1 is not public API",
               "packages/x/lib/x.ex:4: Sib.Hidden is not public API",
               "packages/x/lib/x.ex:5: Sib.Hidden is not public API",
               "packages/x/lib/x.ex:7: Sib.Hidden is not public API"
             ]
    end

    test "distinguishes arities and no-parentheses calls" do
      source = """
      defmodule Consumer do
        alias Sib.Public
        def a, do: Public.secret(1, 2)
        def b, do: Public.secret
        def c, do: Public.secret(1)
      end
      """

      assert messages(source) == ["packages/x/lib/x.ex:5: Sib.Public.secret/1 is not public API"]
    end

    test "aliases are scoped to their block" do
      source = """
      defmodule Consumer do
        def a do
          alias Sib.Public, as: P
          P.secret(1)
        end

        def b, do: P.secret(1)
        def c, do: Public.secret(1)
      end
      """

      assert messages(source) == ["packages/x/lib/x.ex:4: Sib.Public.secret/1 is not public API"]
    end

    test "aliases of the module itself and unrelated modules are ignored" do
      source = """
      defmodule Consumer do
        alias __MODULE__.Helper
        alias Other.Sib.Hidden
        def a, do: Helper.run()
        def b, do: Hidden.anything()
        def c, do: :sib_hidden.anything()
        def d(mod), do: mod.anything()
        def e, do: apply(Sib.Public, :secret, [1])
      end
      """

      assert messages(source) == []
    end

    test "test files and pipelines are analyzed like any expression" do
      source = """
      defmodule ConsumerTest do
        use ExUnit.Case
        alias Sib.Public

        test "x" do
          assert 1 |> Public.secret() == :ok
          Enum.map([1], &Public.secret/1)
          Enum.map([1], fn x -> Sib.Hidden.anything(x) end)
        end
      end
      """

      assert messages(source) == [
               "packages/x/lib/x.ex:6: Sib.Public.secret/1 is not public API",
               "packages/x/lib/x.ex:7: Sib.Public.secret/1 is not public API",
               "packages/x/lib/x.ex:8: Sib.Hidden.anything/1 is not public API"
             ]
    end

    test "a parse failure is a finding" do
      assert [finding] =
               Boundary.analyze("defmodule Broken do\n  def x(, do: 1\nend\n", "b.ex", index())

      assert finding.file == "b.ex"
      assert finding.line == 2
      assert finding.message =~ "cannot be parsed"
    end

    test "a public reference produces nothing" do
      assert Boundary.analyze(
               "defmodule Ok do\n  def a, do: Sib.Public.open(1)\nend\n",
               "ok.ex",
               index()
             ) == []
    end
  end

  describe "index_beam/1" do
    setup context do
      root = Fixtures.tmp_dir(context)

      source = """
      defmodule Wotex.BoundaryFixture.Hidden do
        @moduledoc false
        def x, do: 1
      end

      defmodule Wotex.BoundaryFixture.Public do
        @moduledoc "Public"
        @doc "open"
        def open(a), do: a
        @doc false
        def secret(a), do: a
        @doc false
        defmacro hidden_macro, do: 1
      end
      """

      # `mix test` compiles with `docs: false`; the fixture beams need the
      # Docs chunk that real package builds carry.
      previous = Code.get_compiler_option(:docs)
      Code.put_compiler_option(:docs, true)

      compiled =
        try do
          Code.compile_string(source, "fixture.ex")
        after
          Code.put_compiler_option(:docs, previous)
        end

      for {module, binary} <- compiled do
        File.write!(Path.join(root, "#{module}.beam"), binary)
        :code.purge(module)
        :code.delete(module)
      end

      %{root: root}
    end

    test "reads hidden modules and hidden functions from the docs chunk", %{root: root} do
      assert Boundary.index_beam(Path.join(root, "Elixir.Wotex.BoundaryFixture.Hidden.beam")) ==
               {"Wotex.BoundaryFixture.Hidden", true, []}

      assert {"Wotex.BoundaryFixture.Public", false, hidden} =
               Boundary.index_beam(Path.join(root, "Elixir.Wotex.BoundaryFixture.Public.beam"))

      assert Enum.sort(hidden) == [{:hidden_macro, 0}, {:secret, 1}]
    end

    test "index/1 collects every beam of the directories", %{root: root} do
      index = Boundary.index([root, Path.join(root, "missing")])
      assert MapSet.member?(index.modules, "Wotex.BoundaryFixture.Public")
      assert MapSet.member?(index.hidden_modules, "Wotex.BoundaryFixture.Hidden")
      assert MapSet.member?(index.hidden_functions, {"Wotex.BoundaryFixture.Public", :secret, 1})
      refute MapSet.member?(index.hidden_functions, {"Wotex.BoundaryFixture.Public", :open, 1})
    end

    test "ebin_dir/2 follows the Mix build layout" do
      assert Boundary.ebin_dir("/r/packages/wotex-coap", "wotex_runtime") ==
               "/r/packages/wotex-coap/_build/test/lib/wotex_runtime/ebin"
    end
  end
end
