defmodule Wotex.Lab.CookbookCatalogueTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.{Cookbook, Documentation, Error}

  # The notebook catalogue and Livebook source parsing need no cohort, broker
  # or notebook execution; those runs stay in `Wotex.Lab.CookbookTest` behind
  # the integration tag.
  @root Path.expand("../../..", __DIR__)
  {:ok, docs} = Documentation.directory(@root)
  @docs docs
  @spec_path "specs/WLB.07-cookbooks-and-machine-interfaces.md"

  test "the catalogue lists the sixteen WLB.07 rows in the spec's order" do
    table_ids =
      @docs
      |> Path.join(@spec_path)
      |> File.read!()
      |> then(&Regex.scan(~r/^\| ([a-z][a-z-]*) \| /m, &1))
      |> Enum.map(&Enum.at(&1, 1))
      |> Enum.reject(&(&1 == "id"))

    assert length(table_ids) == 16
    assert Enum.map(Cookbook.list(), & &1.id) == table_ids

    for entry <- Cookbook.list() do
      assert File.regular?(Path.join(@root, entry.path))
      assert entry.evidence in [:executable, :partial]
      assert entry.lane in [:implemented, :partial, :planned]
      assert entry.checks == Enum.uniq(entry.checks)
      assert {:ok, ^entry} = Cookbook.fetch(entry.id)
      assert {:ok, source} = Cookbook.read(entry.id)
      assert String.starts_with?(source, "# ")
    end
  end

  test "unknown ids and unreadable notebooks are typed errors" do
    assert {:error, %Error{code: :unknown_cookbook}} = Cookbook.fetch("nope")
    assert {:error, %Error{code: :unknown_cookbook}} = Cookbook.fetch(:nope)
    assert {:error, %Error{code: :unknown_cookbook}} = Cookbook.read("nope")
  end

  test "cells, headings and missing sections are parsed from Livebook source" do
    source =
      "# T\r\n\r\n## Goal\r\n\r\n```elixir\r\nx = 1\r\ny = 2\r\n```\r\n\r\n```text\r\nnot a cell\r\n```\r\n\r\n```elixir\r\nx + y\r\n```\r\n"

    assert Cookbook.cells(source) == ["x = 1\ny = 2", "x + y"]
    assert Cookbook.headings(source) == ["Goal"]
    assert Cookbook.missing_sections(source) == Cookbook.required_sections() -- ["Goal"]
    assert Cookbook.cells("") == []
  end
end
