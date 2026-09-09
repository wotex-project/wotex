defmodule WotexContinuum.Artifact do
  @moduledoc """
  Immutable identity for an artifact named by a continuum manifest.

  Name and semantic version identify the artifact contract while the lowercase
  SHA-256 digest binds the exact bytes. The value contains no fetch location or
  installation callback, so acquisition and trust policy stay with the
  consumer.

  `from_map/1` validates a bounded artifact name, semantic version, and
  lowercase prefixed digest. Existing structs are converted and revalidated at
  the boundary. `to_map/1` returns the nested string-keyed representation used
  by `WotexContinuum.Manifest`.

  Name and version support compatibility reasoning; the digest is the identity
  for a concrete artifact. Neither field proves availability, authenticity, or
  adoption by a running consumer. Retrieval, signature verification,
  installation, activation, and rollback remain outside this inert value.
  """

  alias WotexContinuum.{Error, Validation}

  @enforce_keys [:name, :version, :digest]
  defstruct [:name, :version, :digest]

  @type t :: %__MODULE__{name: String.t(), version: String.t(), digest: String.t()}

  @doc "Constructs a validated artifact identity."
  @spec from_map(map() | t()) :: {:ok, t()} | {:error, Error.t()}
  def from_map(%__MODULE__{} = value), do: from_map(Map.from_struct(value))

  def from_map(data) do
    with {:ok, data} <- Validation.normalize(data, [:name, :version, :digest]),
         {:ok, name} <- Validation.required(data, :name),
         {:ok, name} <- Validation.string(name, "/name"),
         {:ok, version} <- Validation.required(data, :version),
         {:ok, version} <- Validation.semver(version, "/version"),
         {:ok, digest} <- Validation.required(data, :digest),
         {:ok, digest} <- Validation.digest(digest, "/digest") do
      {:ok, %__MODULE__{name: name, version: version, digest: digest}}
    end
  end

  @doc "Alias of `from_map/1` retained for the 0.1 constructor API."
  @spec new(map() | t()) :: {:ok, t()} | {:error, Error.t()}
  def new(data), do: from_map(data)

  @doc "Returns the wire map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{"name" => value.name, "version" => value.version, "digest" => value.digest}
  end
end
