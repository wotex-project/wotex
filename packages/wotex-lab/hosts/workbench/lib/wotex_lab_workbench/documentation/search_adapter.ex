defmodule WotexLabWorkbench.Documentation.SearchAdapter do
  @moduledoc """
  Adds the canonical DocShell records to Phoenix Assets' pinned Pagefind tree.

  Pagefind remains the browser index; `search-records.json` is the complete
  renderer-neutral machine corpus used for parity and downstream consumers.
  """

  @doc "Builds Pagefind assets and the canonical machine-readable record set."
  @spec build([struct()], keyword()) :: {:ok, struct()} | {:error, term()}
  def build(records, options) do
    adapter = PhoenixAssets.DocShell.Pagefind

    with true <- Code.ensure_loaded?(adapter) and function_exported?(adapter, :build, 2),
         {:ok, output} <- adapter.build(records, options),
         {:ok, bytes} <- canonical_records(records),
         asset <-
           struct!(DocShell.Presentation.Asset,
             path: "search-records.json",
             media_type: "application/json",
             bytes: bytes
           ) do
      contract =
        output.contract
        |> Map.put("records_path", "search-records.json")
        |> update_in(["digests"], &Map.put(&1, asset.path, digest(bytes)))

      {:ok, %{output | assets: Enum.concat(output.assets, [asset]), contract: contract}}
    else
      false -> {:error, :pagefind_candidate_unavailable}
      {:error, _} = error -> error
    end
  end

  defp canonical_records(records) do
    canonical = DocShell.Json.Canonical

    if Code.ensure_loaded?(canonical) and function_exported?(canonical, :encode, 1) do
      records
      |> Enum.map(&Map.from_struct/1)
      |> then(&canonical.encode/1)
    else
      {:error, :doc_shell_site_candidate_required}
    end
  end

  defp digest(bytes),
    do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
