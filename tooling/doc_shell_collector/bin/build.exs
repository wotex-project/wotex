defmodule Wotex.DocShellCollector.Build do
  @moduledoc false

  @spec run([String.t()]) :: :ok
  def run(["--source", source_id]) do
    expected = System.fetch_env!("WOTEX_DOC_SHELL_SOURCE_ID")

    if source_id != expected do
      abort("source argument does not match the admitted environment")
    end

    source_root = System.fetch_env!("WOTEX_DOC_SHELL_SOURCE_ROOT")
    public_dir = System.fetch_env!("WOTEX_DOC_SHELL_PUBLIC_DIR")

    collection = [
      id: String.replace(source_id, "-", "_"),
      title: System.fetch_env!("WOTEX_DOC_SHELL_TITLE"),
      version: System.fetch_env!("WOTEX_DOC_SHELL_VERSION"),
      revision: System.fetch_env!("WOTEX_DOC_SHELL_REVISION"),
      tree_digest: System.fetch_env!("WOTEX_DOC_SHELL_TREE_DIGEST"),
      artifact_dir: public_dir,
      source_url:
        System.fetch_env!("WOTEX_DOC_SHELL_REPOSITORY_URL") <>
          "/tree/" <> System.fetch_env!("WOTEX_DOC_SHELL_REVISION"),
      edit_base_url:
        System.fetch_env!("WOTEX_DOC_SHELL_REPOSITORY_URL") <>
          "/edit/" <> System.fetch_env!("WOTEX_DOC_SHELL_EDIT_BRANCH"),
      license: System.fetch_env!("WOTEX_DOC_SHELL_LICENSE"),
      source_root: source_root,
      status: "stable"
    ]

    case DocShell.Build.run(
           modules: [],
           title: System.fetch_env!("WOTEX_DOC_SHELL_TITLE"),
           api_version: System.fetch_env!("WOTEX_DOC_SHELL_VERSION"),
           public_dir: public_dir,
           private_dir: System.fetch_env!("WOTEX_DOC_SHELL_PRIVATE_DIR"),
           guide_bases: [source_root],
           livebook_base: source_root,
           changelog_source: false,
           collection: collection
         ) do
      {:ok, result} ->
        count = length(result.guides) + length(result.livebooks)
        IO.puts("Generated #{source_id} DocShell collection with #{count} documents")

      {:error, reason} ->
        abort("DocShell collection failed: #{inspect(reason)}")
    end
  end

  def run(_), do: abort("usage: mix run --no-start bin/build.exs -- --source SOURCE_ID")

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.DocShellCollector.Build.run(System.argv())
