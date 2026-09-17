defmodule Wotex.Lab.Test.SourceTree do
  @moduledoc false

  alias Wotex.Lab.Documentation
  alias Wotex.Lab.Evidence.Digest

  @doc """
  Digests package files and documentation as one source tree.

  `files` are catalogue-style paths: `docs/…` names the documentation tree
  `Wotex.Lab.Documentation` locates, everything else is relative to the
  package at `root`. Both are digested relative to the checkout that holds
  them, so the recorded paths are the repository's real paths.
  """
  @spec digest(Path.t(), [String.t()]) :: {:ok, String.t()} | {:error, term()}
  def digest(root, files) do
    root = Path.expand(root)
    {:ok, docs} = Documentation.directory(root)
    base = common_parent(root, docs)

    patterns =
      Enum.map(files, fn
        "docs/" <> rest -> Path.relative_to(Path.join(docs, rest), base)
        other -> Path.relative_to(Path.join(root, other), base)
      end)

    Digest.tree(base, patterns)
  end

  defp common_parent(left, right) do
    [Path.split(left), Path.split(right)]
    |> Enum.zip()
    |> Enum.take_while(fn {a, b} -> a == b end)
    |> Enum.map(&elem(&1, 0))
    |> Path.join()
  end
end
