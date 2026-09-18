defmodule WotexLabWorkbench.Provenance do
  @moduledoc """
  Compile-time provenance of the Lab artifact this host was built against.

  Everything here is read once while the host compiles: the Lab source tree
  digest, the host lock digest, the exact dependency versions with their Hex
  archive digests (path dependencies record `:missing` because a checkout is
  not an archive), the fixture and model digests, the specification digests
  and the Lab's own source cohort and source index. Nothing is read from the
  filesystem or the network at runtime, and a host built from a workspace
  checkout says so through `source_mode/0`.
  """

  alias Wotex.Lab.Documentation
  alias Wotex.Lab.Evidence.Digest

  @lab_path Mix.Project.deps_paths()[:wotex_lab]
  @lock Mix.Dep.Lock.read()
  dependency_versions =
    Map.new(Mix.Dep.cached(), fn dependency ->
      version =
        case dependency.status do
          {:ok, value} when is_binary(value) -> value
          {:nomatchvsn, value} when is_binary(value) -> value
          _ -> "unavailable"
        end

      {dependency.app, version}
    end)

  # A source checkout keeps its specifications in the documentation tree, which
  # only `Wotex.Lab.Documentation` locates; a Hex archive ships none and
  # records no specification digests.
  @docs_path (case Documentation.directory(@lab_path) do
                {:ok, directory} -> directory
                :error -> nil
              end)
  @external_resource Path.join(@lab_path, "priv/provenance/source-cohort.json")
  @external_resource Path.join(@lab_path, "priv/provenance/source-index.json")
  @external_resource "mix.lock"

  @source_mode if(Map.has_key?(@lock, :wotex_lab), do: "hex artifact", else: "workspace path")
  @lock_digest Digest.bytes(File.read!("mix.lock"))
  @source_tree_digest elem(
                        Digest.tree(@lab_path, ["lib/**/*.ex", "mix.exs", "priv/**/*"]),
                        1
                      )
  @fixtures Map.new(
              Path.wildcard(Path.join(@lab_path, "priv/{fixtures,models}/**/*.{json,maude}")),
              fn path ->
                {Path.relative_to(path, Path.join(@lab_path, "priv")), Digest.file!(path)}
              end
            )
  @specs Map.new(
           if(@docs_path, do: Path.wildcard(Path.join(@docs_path, "specs/WLB.*.md")), else: []),
           fn path -> {Path.basename(path), Digest.file!(path)} end
         )
  @cohort @lab_path
          |> Path.join("priv/provenance/source-cohort.json")
          |> File.read!()
          |> JSON.decode!()
  @index @lab_path
         |> Path.join("priv/provenance/source-index.json")
         |> File.read!()
         |> JSON.decode!()
  @dependencies Enum.map(
                  ~w(wotex_lab wotex wotex_nx wotex_runtime wotex_directory wotex_continuum
                     wotex_binding_http wotex_binding_mqtt nx ex_maude phoenix phoenix_live_view)a,
                  fn name ->
                    case Map.get(@lock, name) do
                      {:hex, _, version, _, _, _, _, outer} ->
                        %{name: Atom.to_string(name), version: version, archive: "sha256:" <> outer}

                      _ ->
                        version = Map.get(dependency_versions, name, "absent")

                        %{name: Atom.to_string(name), version: version, archive: :missing}
                    end
                  end
                )

  @doc "`hex artifact` when the Lab came from a lock entry, `workspace path` for a checkout."
  @spec source_mode() :: String.t()
  def source_mode, do: @source_mode

  @doc "Digest of the host's mix.lock at build time."
  @spec lock_digest() :: String.t()
  def lock_digest, do: @lock_digest

  @doc "Digest of the Lab source tree the host compiled against."
  @spec source_tree_digest() :: String.t()
  def source_tree_digest, do: @source_tree_digest

  @doc "Dependency versions with archive digests, or `:missing` for checkouts."
  @spec dependencies() :: [%{name: String.t(), version: String.t(), archive: String.t() | :missing}]
  def dependencies, do: @dependencies

  @doc "Fixture and model digests keyed by their `priv` relative path."
  @spec fixtures() :: %{String.t() => String.t()}
  def fixtures, do: @fixtures

  @doc "Lab specification digests keyed by file name."
  @spec specs() :: %{String.t() => String.t()}
  def specs, do: @specs

  @doc "The Lab's inspected workspace content cohort."
  @spec cohort() :: map()
  def cohort, do: @cohort

  @doc "The Lab's historical source baseline: immutable revisions and catalogue digests."
  @spec source_index() :: map()
  def source_index, do: @index
end
