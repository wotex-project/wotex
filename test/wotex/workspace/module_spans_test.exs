defmodule Wotex.Workspace.ModuleSpansTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.ModuleSpans

  defp spans!(source) do
    {:ok, spans} = ModuleSpans.spans(source)
    Enum.map(spans, &{&1.module, &1.first, &1.last})
  end

  describe "spans/2" do
    test "a source without modules has no spans" do
      assert ModuleSpans.spans("") == {:ok, []}
      assert ModuleSpans.spans("Mix.install([])\nIO.puts(:ok)\n") == {:ok, []}
    end

    test "returns maps with the module and its first and last line" do
      assert ModuleSpans.spans("defmodule A do\n  def a, do: 1\nend\n") ==
               {:ok, [%{module: "A", first: 1, last: 3}]}
    end

    test "nests dotted and __MODULE__ names, outermost first" do
      source = """
      defmodule A.B do
        defmodule C.D do
          defmodule __MODULE__.E do
          end
        end
      end

      defmodule F do
      end
      """

      assert spans!(source) == [
               {"A.B", 1, 6},
               {"A.B.C.D", 2, 5},
               {"A.B.C.D.E", 3, 4},
               {"F", 8, 9}
             ]
    end

    test "Elixir-prefixed and atom names are not nested" do
      source = """
      defmodule Outer do
        defmodule Elixir.Absolute do
        end

        defmodule :erlang_style do
        end

        defmodule :"Elixir.Quoted.Atom" do
        end
      end
      """

      assert spans!(source) == [
               {"Outer", 1, 10},
               {"Absolute", 2, 3},
               {"erlang_style", 5, 6},
               {"Quoted.Atom", 8, 9}
             ]
    end

    test "defprotocol is a module and defimpl is not" do
      source = """
      defmodule Outer do
        defprotocol Shape do
          def area(shape)
        end
      end

      defimpl Outer.Shape, for: Map do
        def area(_map), do: 0
      end
      """

      assert spans!(source) == [{"Outer", 1, 5}, {"Outer.Shape", 2, 4}]
      assert ModuleSpans.enclosing(source, 8) == {:ok, nil}
    end

    test "a module with a computed name belongs to the enclosing module" do
      source = """
      defmodule Outer do
        for name <- [One, Two] do
          defmodule name do
            def id, do: 1
          end
        end

        defmacro define(name) do
          quote do
            defmodule unquote(name) do
            end
          end
        end
      end

      defmodule __MODULE__.Orphan do
      end
      """

      assert spans!(source) == [{"Outer", 1, 14}]
      assert ModuleSpans.enclosing(source, 4) == {:ok, "Outer"}
      assert ModuleSpans.enclosing(source, 10) == {:ok, "Outer"}
      assert ModuleSpans.enclosing(source, 16) == {:ok, nil}
    end

    test "module names in strings and documentation are not modules" do
      source = ~S'''
      @doc "defmodule Fake do"
      defmodule Real do
        @moduledoc """
        defmodule Also.Fake do
        end
        """
      end
      '''

      assert spans!(source) == [{"Real", 2, 7}]
    end

    test "the keyword form ends at the last line of its body" do
      source = """
      defmodule Short, do: def(a, do: 1)

      defmodule Long,
        do: (
          import Bitwise
          alias Short
        )

      x = 1
      """

      assert spans!(source) == [{"Short", 1, 1}, {"Long", 3, 6}]
      assert ModuleSpans.enclosing(source, 9) == {:ok, nil}
    end

    test "a parse failure names the file and the line" do
      assert {:error, message} =
               ModuleSpans.spans(~s(defmodule A do\n  x = "abc\nend\n), "lib/a.ex")

      assert message =~ ~r/^lib\/a\.ex:2: cannot be parsed: missing terminator: "/

      assert {:error, "nofile:1: cannot be parsed: " <> reason} =
               ModuleSpans.spans("defmodule A do\n")

      assert reason =~ "missing terminator"
    end
  end

  describe "enclosing/3" do
    test "the defmodule and end lines belong to the module" do
      source = """
      # A comment.
      defmodule A do
        def a, do: 1
      end

      defmodule B do
      end
      """

      assert for(line <- 1..9, do: elem(ModuleSpans.enclosing(source, line), 1)) ==
               [nil, "A", "A", "A", nil, "B", "B", nil, nil]
    end

    test "on a shared first line the shorter span is innermost" do
      source = "defmodule A do defmodule B do\n  def x, do: 1\nend\nend\n"

      assert spans!(source) == [{"A", 1, 4}, {"A.B", 1, 3}]
      assert ModuleSpans.enclosing(source, 1) == {:ok, "A.B"}
      assert ModuleSpans.enclosing(source, 3) == {:ok, "A.B"}
      assert ModuleSpans.enclosing(source, 4) == {:ok, "A"}
    end

    test "returns the parse error of spans/2" do
      source = "defmodule A do\n"

      assert {:error, message} = ModuleSpans.enclosing(source, 1, "lib/a.ex")
      assert ModuleSpans.spans(source, "lib/a.ex") == {:error, message}
    end
  end
end
