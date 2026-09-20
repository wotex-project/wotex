defmodule Wotex.Lab.Docs.Checkout do
  @moduledoc """
  Opens one detached, source-specific Git checkout for documentation work.

  Every source receives its own work directory. A local repository override is
  a qualification input only; the checked-out revision must still match the
  immutable catalogue identity exactly.
  """

  alias Wotex.Lab.Docs.CommandEnvironment

  @doc "Clones and checks out one catalogue source at its exact revision."
  @spec open(map(), Path.t(), keyword()) :: {:ok, Path.t()} | {:error, term()}
  def open(source, destination, opts \\ []) do
    with :ok <- validate_options(opts),
         :ok <- validate_destination(destination) do
      open_new(source, destination, opts)
    end
  end

  defp open_new(source, destination, opts) do
    origin = Keyword.get(opts, :repository, source["repository_url"])

    result =
      with :ok <- validate_origin(origin),
           :ok <- clone(origin, destination),
           :ok <- checkout(destination, source["revision"]),
           :ok <- verify_head(destination, source["revision"]),
           :ok <- verify_clean(destination) do
        {:ok, destination}
      end

    case result do
      {:ok, _} = success ->
        success

      {:error, _} = error ->
        cleanup(destination)
        error
    end
  end

  defp validate_options(opts) do
    if Keyword.keyword?(opts) and Keyword.keys(opts) -- [:repository] == [],
      do: :ok,
      else: {:error, {:invalid_checkout_options, opts}}
  end

  defp validate_destination(destination) do
    cond do
      not is_binary(destination) or Path.type(destination) != :absolute ->
        {:error, {:invalid_checkout_destination, destination}}

      File.exists?(destination) ->
        {:error, {:occupied_checkout_destination, destination}}

      true ->
        :ok
    end
  end

  defp validate_origin(origin) when is_binary(origin) and origin != "" do
    cond do
      Path.type(origin) == :absolute and File.dir?(origin) -> :ok
      https_github?(origin) -> :ok
      true -> {:error, {:invalid_checkout_origin, origin}}
    end
  end

  defp validate_origin(origin), do: {:error, {:invalid_checkout_origin, origin}}

  defp clone(origin, destination) do
    args =
      if Path.type(origin) == :absolute do
        ["clone", "--quiet", "--shared", "--no-checkout", origin, destination]
      else
        ["clone", "--quiet", "--filter=blob:none", "--no-checkout", origin, destination]
      end

    git(nil, args, :clone)
  end

  defp checkout(repository, revision),
    do: git(repository, ["checkout", "--quiet", "--detach", revision], :checkout)

  defp verify_head(repository, revision) do
    case System.cmd("git", ["-C", repository, "rev-parse", "HEAD"],
           stderr_to_stdout: true,
           env: CommandEnvironment.scrubbed()
         ) do
      {output, 0} ->
        if String.trim(output) == revision,
          do: :ok,
          else: {:error, {:checkout_revision_mismatch, revision, String.trim(output)}}

      {output, status} ->
        {:error, {:git_checkout_head_failed, status, message(output)}}
    end
  end

  defp verify_clean(repository) do
    case System.cmd(
           "git",
           ["-C", repository, "status", "--porcelain", "--untracked-files=no"],
           stderr_to_stdout: true,
           env: CommandEnvironment.scrubbed()
         ) do
      {"", 0} -> :ok
      {output, 0} -> {:error, {:dirty_source_checkout, message(output)}}
      {output, status} -> {:error, {:git_status_failed, status, message(output)}}
    end
  end

  defp git(nil, args, operation) do
    case System.cmd("git", args,
           stderr_to_stdout: true,
           env: CommandEnvironment.scrubbed()
         ) do
      {_, 0} -> :ok
      {output, status} -> {:error, {:git_operation_failed, operation, status, message(output)}}
    end
  end

  defp git(repository, args, operation) do
    case System.cmd("git", ["-C", repository | args],
           stderr_to_stdout: true,
           env: CommandEnvironment.scrubbed()
         ) do
      {_, 0} -> :ok
      {output, status} -> {:error, {:git_operation_failed, operation, status, message(output)}}
    end
  end

  defp https_github?(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: "github.com", query: nil, fragment: nil} -> true
      _ -> false
    end
  end

  defp cleanup(destination) when is_binary(destination) do
    if Path.type(destination) == :absolute and File.dir?(destination), do: File.rm_rf(destination)
    :ok
  end

  defp cleanup(_), do: :ok

  defp message(output) do
    output
    |> String.slice(0, 2_048)
    |> String.trim()
  end
end
