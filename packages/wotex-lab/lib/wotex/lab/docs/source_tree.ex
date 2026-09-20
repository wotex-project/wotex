defmodule Wotex.Lab.Docs.SourceTree do
  @moduledoc """
  Resolves immutable Git source trees for documentation builds.

  A tree digest covers the exact recursive `git ls-tree` records for the
  declared roots. It therefore binds paths, object modes, object types and blob
  identities without reading mutable working-tree files. Symlinks and gitlinks
  are rejected before a source can enter the documentation pipeline.
  """

  alias Wotex.Lab.Docs.CommandEnvironment

  @algorithm "sha256-git-ls-tree-v1"
  @revision ~r/\A[0-9a-f]{40}\z/
  @digest ~r/\Asha256:[0-9a-f]{64}\z/

  @typedoc "A verified immutable source tree."
  @type verified :: %{
          revision: String.t(),
          tree_digest: String.t(),
          files: [Path.t()]
        }

  @doc "The tree-digest algorithm recorded in the documentation catalogue."
  @spec algorithm() :: String.t()
  def algorithm, do: @algorithm

  @doc "Computes and returns the exact tracked file inventory for declared roots."
  @spec verify(Path.t(), String.t(), [Path.t()]) :: {:ok, verified()} | {:error, term()}
  def verify(repository, revision, roots) do
    with :ok <- validate_repository(repository),
         :ok <- validate_revision(revision),
         {:ok, roots} <- validate_roots(roots),
         :ok <- commit_exists(repository, revision),
         :ok <- roots_exist(repository, revision, roots),
         {:ok, bytes} <- ls_tree(repository, revision, roots),
         {:ok, files} <- parse_tree(bytes, roots) do
      {:ok,
       %{
         revision: revision,
         tree_digest: digest(bytes),
         files: files
       }}
    end
  end

  @doc "Checks a catalogue digest against the immutable Git tree."
  @spec verify_digest(Path.t(), String.t(), [Path.t()], String.t()) ::
          {:ok, verified()} | {:error, term()}
  def verify_digest(repository, revision, roots, expected) do
    with true <- is_binary(expected) and Regex.match?(@digest, expected),
         {:ok, %{tree_digest: actual} = source} <- verify(repository, revision, roots),
         true <- actual == expected do
      {:ok, source}
    else
      false -> {:error, {:source_tree_digest_mismatch, expected}}
      {:error, _} = error -> error
    end
  end

  @doc "Reads one tracked blob from an already verified revision."
  @spec read(Path.t(), String.t(), Path.t()) :: {:ok, binary()} | {:error, term()}
  def read(repository, revision, path) do
    with :ok <- validate_repository(repository),
         :ok <- validate_revision(revision),
         true <- relative_path?(path),
         {bytes, 0} <- git(repository, ["show", "#{revision}:#{path}"]) do
      {:ok, bytes}
    else
      false -> {:error, {:invalid_source_path, path}}
      {:error, _} = error -> error
      {output, status} -> {:error, {:git_show_failed, path, status, message(output)}}
    end
  end

  defp validate_repository(repository) do
    if is_binary(repository) and Path.type(repository) == :absolute and File.dir?(repository),
      do: :ok,
      else: {:error, {:invalid_source_repository, repository}}
  end

  defp validate_revision(revision) do
    if is_binary(revision) and Regex.match?(@revision, revision),
      do: :ok,
      else: {:error, {:invalid_source_revision, revision}}
  end

  defp validate_roots(roots) when is_list(roots) and roots != [] do
    if roots == Enum.uniq(roots) and Enum.all?(roots, &relative_path?/1),
      do: {:ok, roots},
      else: {:error, {:invalid_documentation_roots, roots}}
  end

  defp validate_roots(roots), do: {:error, {:invalid_documentation_roots, roots}}

  defp commit_exists(repository, revision) do
    case git(repository, ["cat-file", "-e", "#{revision}^{commit}"]) do
      {_, 0} -> :ok
      {output, status} -> {:error, {:missing_source_revision, revision, status, message(output)}}
    end
  end

  defp roots_exist(repository, revision, roots) do
    Enum.reduce_while(roots, :ok, fn root, :ok ->
      case git(repository, ["cat-file", "-e", "#{revision}:#{root}"]) do
        {_, 0} ->
          {:cont, :ok}

        {output, status} ->
          {:halt, {:error, {:missing_documentation_root, root, status, message(output)}}}
      end
    end)
  end

  defp ls_tree(repository, revision, roots) do
    case git(repository, ["ls-tree", "-r", "-z", "--full-tree", revision, "--" | roots]) do
      {"", 0} -> {:error, :empty_source_tree}
      {bytes, 0} -> {:ok, bytes}
      {output, status} -> {:error, {:git_ls_tree_failed, status, message(output)}}
    end
  end

  defp parse_tree(bytes, roots) do
    result =
      bytes
      |> :binary.split(<<0>>, [:global])
      |> Enum.reject(&(&1 == ""))
      |> Enum.reduce_while({:ok, []}, fn entry, {:ok, files} ->
        case parse_entry(entry, roots) do
          {:ok, path} -> {:cont, {:ok, [path | files]}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case result do
      {:ok, []} -> {:error, :empty_source_tree}
      {:ok, files} -> {:ok, Enum.reverse(files)}
      error -> error
    end
  end

  defp parse_entry(entry, roots) do
    case :binary.split(entry, "\t") do
      [header, path] -> validate_entry(String.split(header, " "), path, roots)
      _ -> {:error, {:invalid_git_tree_entry, entry}}
    end
  end

  defp validate_entry(["120000", "blob", _], path, _),
    do: {:error, {:symlinked_documentation_source, path}}

  defp validate_entry(["160000", "commit", _], path, _),
    do: {:error, {:gitlink_documentation_source, path}}

  defp validate_entry([mode, "blob", object], path, roots) do
    if Regex.match?(~r/\A100[0-7]{3}\z/, mode) and Regex.match?(~r/\A[0-9a-f]{40,64}\z/, object) and
         Enum.any?(roots, &inside_root?(path, &1)) do
      {:ok, path}
    else
      {:error, {:invalid_git_tree_entry, path}}
    end
  end

  defp validate_entry(_, path, _), do: {:error, {:invalid_git_tree_entry, path}}

  defp inside_root?(path, root), do: path == root or String.starts_with?(path, root <> "/")

  defp relative_path?(path) when is_binary(path) and path != "" do
    Path.type(path) == :relative and ".." not in Path.split(path) and
      not String.contains?(path, ["\\", <<0>>])
  end

  defp relative_path?(_), do: false

  defp git(repository, args) do
    System.cmd("git", ["-C", repository | args],
      stderr_to_stdout: true,
      env: CommandEnvironment.scrubbed()
    )
  end

  defp digest(bytes),
    do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp message(output) when is_binary(output) do
    output
    |> String.slice(0, 2_048)
    |> String.trim()
  end
end
