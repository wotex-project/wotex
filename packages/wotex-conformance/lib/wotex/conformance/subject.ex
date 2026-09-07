defmodule Wotex.Conformance.Subject do
  @moduledoc """
  Immutable identity of the subject tested by a conformance run.

  Local artifact paths and endpoint credentials are execution configuration and
  are deliberately absent from this reportable value.
  """

  alias Wotex.Conformance.{Canonical, Error, Input, Value}

  @enforce_keys [:id, :version, :artifact_digest, :interface]
  defstruct [:id, :version, :artifact_digest, :interface]

  @type t :: %__MODULE__{
          id: String.t(),
          version: String.t(),
          artifact_digest: String.t(),
          interface: %{String.t() => Value.json_value()}
        }

  @doc "Constructs an immutable subject identity from decoded input."
  @spec from_map(map()) :: {:ok, t()} | {:error, Error.t()}
  def from_map(input) when is_map(input) do
    with :ok <- Input.only_keys(input, ~w(id version artifact_digest interface)),
         {:ok, id_input} <- Input.required(input, :id),
         {:ok, id} <- Value.validate_identifier(id_input, "id"),
         {:ok, version_input} <- Input.required(input, :version),
         {:ok, version} <- Value.validate_identifier(version_input, "version", max_bytes: 128),
         {:ok, digest} <- validate_digest(Input.optional(input, :artifact_digest, nil)),
         {:ok, interface_input} <- Input.required(input, :interface),
         {:ok, interface} <- validate_interface(interface_input) do
      {:ok,
       %__MODULE__{
         id: id,
         version: version,
         artifact_digest: digest,
         interface: interface
       }}
    end
  end

  def from_map(_input),
    do: {:error, Error.new(:invalid_type, :subject, "subject must be an object")}

  @doc "Alias for `from_map/1`, the map-shaped subject constructor."
  @spec new(map()) :: {:ok, t()} | {:error, Error.t()}
  def new(input), do: from_map(input)

  @doc "Serializes a subject identity to its string-keyed report form."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = subject) do
    %{
      "id" => subject.id,
      "version" => subject.version,
      "artifact_digest" => subject.artifact_digest,
      "interface" => subject.interface
    }
  end

  defp validate_digest(digest) do
    if Canonical.valid_digest?(digest) do
      {:ok, digest}
    else
      {:error,
       Error.new(:invalid_digest, :subject, "artifact_digest must be lowercase SHA-256",
         path: ["artifact_digest"]
       )}
    end
  end

  defp validate_interface(value) do
    with {:ok, interface} <- Value.string_key_map(value, "interface"),
         {:ok, _validated} <-
           Value.validate(interface, max_depth: 8, max_nodes: 64, max_string_bytes: 512),
         {:ok, kind} <- required_interface_identifier(interface, "kind"),
         {:ok, revision} <- required_interface_identifier(interface, "revision") do
      {:ok, Map.merge(interface, %{"kind" => kind, "revision" => revision})}
    end
  end

  defp required_interface_identifier(interface, key) do
    case Map.fetch(interface, key) do
      {:ok, value} ->
        Value.validate_identifier(value, key, max_bytes: 128)

      :error ->
        {:error,
         Error.new(:missing_field, :subject, "interface #{key} is required",
           path: ["interface", key]
         )}
    end
  end
end
