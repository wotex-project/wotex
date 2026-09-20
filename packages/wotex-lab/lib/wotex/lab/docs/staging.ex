defmodule Wotex.Lab.Docs.Staging do
  @moduledoc """
  Materializes the admitted public documents from an immutable Git revision.

  Bytes come from Git objects, never the caller's working tree. The destination
  must be a new absolute directory owned by the build lane; a failed copy
  removes that incomplete directory.
  """

  alias Wotex.Lab.Docs.{Admission, SourceTree}

  @typedoc "A staged, exact public source inventory."
  @type staged :: %{
          root: Path.t(),
          files: [Path.t()],
          tree_digest: String.t(),
          revision: String.t()
        }

  @doc "Verifies one catalogue source and stages only its admitted public files."
  @spec prepare(Path.t(), map(), Path.t()) :: {:ok, staged()} | {:error, term()}
  def prepare(repository, source, destination) do
    with :ok <- validate_destination(destination) do
      prepare_new(repository, source, destination)
    end
  end

  defp prepare_new(repository, source, destination) do
    result =
      with {:ok, verified} <-
             SourceTree.verify_digest(
               repository,
               source["revision"],
               source["documentation_roots"],
               source["tree_digest"]
             ),
           files = Admission.select(verified.files, source["documentation_roots"]),
           :ok <- nonempty(files, source["id"]),
           :ok <- File.mkdir(destination),
           :ok <- copy_files(repository, verified.revision, destination, files) do
        {:ok,
         %{
           root: destination,
           files: files,
           tree_digest: verified.tree_digest,
           revision: verified.revision
         }}
      end

    case result do
      {:ok, _} = success ->
        success

      {:error, _} = error ->
        cleanup(destination)
        error
    end
  end

  defp validate_destination(destination) do
    cond do
      not is_binary(destination) or Path.type(destination) != :absolute ->
        {:error, {:invalid_staging_destination, destination}}

      File.exists?(destination) ->
        {:error, {:occupied_staging_destination, destination}}

      true ->
        :ok
    end
  end

  defp nonempty([], id), do: {:error, {:empty_documentation_source, id}}
  defp nonempty(_, _), do: :ok

  defp copy_files(repository, revision, destination, files) do
    Enum.reduce_while(files, :ok, fn path, :ok ->
      target = Path.join(destination, path)

      with {:ok, bytes} <- SourceTree.read(repository, revision, path),
           :ok <- File.mkdir_p(Path.dirname(target)),
           :ok <- File.write(target, bytes, [:binary, :exclusive]) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, {:stage_documentation_source, path, reason}}}
      end
    end)
  end

  defp cleanup(destination) when is_binary(destination) do
    if Path.type(destination) == :absolute and File.dir?(destination), do: File.rm_rf(destination)
    :ok
  end

  defp cleanup(_), do: :ok
end
