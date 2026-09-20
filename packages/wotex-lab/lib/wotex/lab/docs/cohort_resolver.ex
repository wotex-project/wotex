defmodule Wotex.Lab.Docs.CohortResolver do
  @moduledoc """
  Resolves release and rolling documentation profiles.

  Release input remains exactly as committed. Rolling resolution reads each
  repository branch head once, converts it to an immutable commit, computes
  every source tree digest from that commit, and clears release-only collection
  expectations before any collection build starts.
  """

  alias Wotex.Lab.Docs.{Catalogue, Checkout, CommandEnvironment, SourceTree}

  @allowed_options [:repository_overrides, :workspace]

  @doc "Resolves one build profile into an immutable, validated catalogue."
  @spec resolve(Catalogue.t(), String.t(), keyword()) ::
          {:ok, Catalogue.t()} | {:error, term()}
  def resolve(catalogue, profile, opts \\ [])

  def resolve(catalogue, "release", opts) do
    with :ok <- validate_options(opts),
         true <- catalogue["profile"] == "release",
         :ok <- Catalogue.validate_locked(catalogue) do
      {:ok, catalogue}
    else
      false -> {:error, {:documentation_profile_mismatch, catalogue["profile"], "release"}}
      {:error, _} = error -> error
    end
  end

  def resolve(catalogue, "rolling", opts) do
    with :ok <- validate_options(opts),
         :ok <- Catalogue.validate(catalogue),
         {:ok, workspace, owned?} <- workspace(Keyword.get(opts, :workspace)) do
      result =
        resolve_rolling(catalogue, workspace, Keyword.get(opts, :repository_overrides, %{}))

      cleanup(workspace, owned?)
      result
    end
  end

  def resolve(_, profile, _), do: {:error, {:invalid_documentation_profile, profile}}

  defp resolve_rolling(catalogue, workspace, overrides) do
    groups = Enum.group_by(catalogue["sources"], &{&1["repository_url"], &1["default_branch"]})

    result =
      groups
      |> Enum.sort_by(fn {{url, branch}, _} -> {url, branch} end)
      |> Enum.reduce_while({:ok, %{}}, fn {{url, branch}, sources}, {:ok, identities} ->
        case resolve_repository(url, branch, sources, workspace, overrides) do
          {:ok, resolved} -> {:cont, {:ok, Map.merge(identities, resolved)}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    with {:ok, identities} <- result do
      sources =
        Enum.map(catalogue["sources"], fn source ->
          identity = Map.fetch!(identities, source["id"])

          source
          |> Map.put("revision", identity.revision)
          |> Map.put("tree_digest", identity.tree_digest)
          |> Map.put("expected_collection_digest", nil)
        end)

      resolved =
        catalogue
        |> Map.put("profile", "rolling")
        |> Map.put("sources", sources)

      with :ok <- Catalogue.validate(resolved), do: {:ok, resolved}
    end
  end

  defp resolve_repository(url, branch, sources, workspace, overrides) do
    repository = Map.get(overrides, url)

    with {:ok, revision} <- resolve_head(url, branch, repository),
         seed = hd(sources) |> Map.put("revision", revision),
         checkout = Path.join(workspace, digest_name(url)),
         checkout_opts = if(repository, do: [repository: repository], else: []),
         {:ok, checkout} <- Checkout.open(seed, checkout, checkout_opts) do
      Enum.reduce_while(sources, {:ok, %{}}, fn source, {:ok, identities} ->
        case SourceTree.verify(checkout, revision, source["documentation_roots"]) do
          {:ok, identity} ->
            {:cont, {:ok, Map.put(identities, source["id"], identity)}}

          {:error, reason} ->
            {:halt, {:error, {:rolling_source_tree_failed, source["id"], reason}}}
        end
      end)
    end
  end

  defp resolve_head(_, branch, repository) when is_binary(repository) do
    case System.cmd(
           "git",
           ["-C", repository, "rev-parse", "refs/heads/#{branch}^{commit}"],
           stderr_to_stdout: true,
           env: CommandEnvironment.scrubbed()
         ) do
      {output, 0} -> revision(output, branch)
      {output, status} -> {:error, {:rolling_head_failed, branch, status, tail(output)}}
    end
  end

  defp resolve_head(url, branch, nil) do
    case System.cmd("git", ["ls-remote", "--exit-code", url, "refs/heads/#{branch}"],
           stderr_to_stdout: true,
           env: CommandEnvironment.scrubbed()
         ) do
      {output, 0} -> revision(output, branch)
      {output, status} -> {:error, {:rolling_head_failed, url, branch, status, tail(output)}}
    end
  end

  defp revision(output, context) do
    case String.split(output) do
      [revision | _] ->
        if Regex.match?(~r/\A[0-9a-f]{40}\z/, revision),
          do: {:ok, revision},
          else: {:error, {:invalid_rolling_revision, context, revision}}

      _ ->
        {:error, {:invalid_rolling_revision, context, tail(output)}}
    end
  end

  defp validate_options(opts) do
    if Keyword.keyword?(opts) and Keyword.keys(opts) -- @allowed_options == [] do
      overrides = Keyword.get(opts, :repository_overrides, %{})
      requested_workspace = Keyword.get(opts, :workspace)

      cond do
        not valid_overrides?(overrides) ->
          {:error, {:invalid_repository_overrides, overrides}}

        not is_nil(requested_workspace) and not new_absolute_path?(requested_workspace) ->
          {:error, {:invalid_resolver_workspace, requested_workspace}}

        true ->
          :ok
      end
    else
      {:error, {:invalid_cohort_resolver_options, opts}}
    end
  end

  defp workspace(nil) do
    parent = System.tmp_dir!()
    path = Path.join(parent, "wotex-doc-resolve-#{token()}")

    with :ok <- File.mkdir(path), do: {:ok, path, true}
  end

  defp workspace(path) do
    with :ok <- File.mkdir(path), do: {:ok, path, false}
  end

  defp cleanup(path, true), do: File.rm_rf(path)
  defp cleanup(_, false), do: :ok

  defp valid_overrides?(overrides) when is_map(overrides) do
    Enum.all?(overrides, fn {url, path} ->
      is_binary(url) and is_binary(path) and Path.type(path) == :absolute and File.dir?(path)
    end)
  end

  defp valid_overrides?(_), do: false

  defp new_absolute_path?(path) do
    is_binary(path) and Path.type(path) == :absolute and not File.exists?(path) and
      File.dir?(Path.dirname(path))
  end

  defp digest_name(value) do
    encoded = Base.url_encode64(:crypto.hash(:sha256, value), padding: false)
    binary_part(encoded, 0, 20)
  end

  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)

  defp tail(output) do
    output
    |> String.slice(-8_192, 8_192)
    |> String.trim()
  end
end
