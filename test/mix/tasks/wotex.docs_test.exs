defmodule Mix.Tasks.Wotex.DocsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Docs

  test "takes a name and extra arguments" do
    assert Docs.parse_args(~w(wotex-nx --warnings-as-errors)) ==
             {"wotex-nx", ~w(--warnings-as-errors)}

    assert_raise Mix.Error, fn -> Docs.parse_args([]) end
  end

  test "builds in the docs environment only when the package declares one" do
    assert Docs.docs_env(~s|{:ex_doc, "~> 0.38", only: [:dev, :docs]}|) == "docs"
    assert Docs.docs_env(~s|{:ex_doc, "~> 0.38", only: :dev}|) == nil
  end
end
