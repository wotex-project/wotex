defmodule WotexContinuum.Artifact do
  @moduledoc """
  Immutable artifact identity carried by a continuum manifest.
  """

  alias WotexContinuum.{Error, Validation}

  @enforce_keys [:name, :version, :digest]
  defstruct [:name, :version, :digest]

  @type t :: %__MODULE__{name: String.t(), version: String.t(), digest: String.t()}

  @doc "Constructs a validated artifact identity."
  @spec new(map() | t()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = value), do: {:ok, value}

  def new(data) do
    with {:ok, data} <- Validation.normalize(data, [:name, :version, :digest]),
         {:ok, name} <- Validation.required(data, :name),
         {:ok, name} <- Validation.string(name, ["name"]),
         {:ok, version} <- Validation.required(data, :version),
         {:ok, version} <- Validation.semver(version, ["version"]),
         {:ok, digest} <- Validation.required(data, :digest),
         {:ok, digest} <- Validation.digest(digest, ["digest"]) do
      {:ok, %__MODULE__{name: name, version: version, digest: digest}}
    end
  end

  @doc "Returns the wire map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{"name" => value.name, "version" => value.version, "digest" => value.digest}
  end
end
