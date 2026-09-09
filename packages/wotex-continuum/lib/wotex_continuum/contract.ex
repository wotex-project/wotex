defmodule WotexContinuum.Contract do
  @moduledoc """
  Shared envelope validation for typed continuum values.

  Value constructors use `envelope/2` to supply absent kind and schema-version
  fields, then `normalize/3` to admit only declared atom or string keys. An
  explicit wrong kind, duplicate key spelling, malformed semantic version, or
  version outside `~> 2.0` returns `WotexContinuum.Error`. Existing envelope
  fields are preserved for validation rather than silently replaced.

  This implementation helper validates wire identity. The owning value module
  validates its payload and cross-field relationships. `base/1` constructs the
  current envelope for serialization; it does not register a kind, authorize an
  interaction, or migrate an older schema.

  ## Examples

      iex> WotexContinuum.Contract.base("mode")
      %{"kind" => "mode", "schema_version" => "2.0.0"}
  """

  alias WotexContinuum.{Error, Validation}

  @spec normalize(map(), [atom()], String.t()) :: {:ok, map()} | {:error, Error.t()}
  def normalize(data, fields, expected_kind) do
    with {:ok, data} <- Validation.normalize(data, [:kind, :schema_version | fields]),
         {:ok, kind} <- Validation.required(data, :kind),
         {:ok, kind} <- Validation.string(kind, "/kind", max: 128),
         :ok <- exact(kind, expected_kind, "/kind", :wrong_kind),
         {:ok, schema_version} <- Validation.required(data, :schema_version),
         {:ok, schema_version} <- Validation.semver(schema_version, "/schema_version"),
         :ok <- supported_schema(schema_version) do
      {:ok, data}
    end
  end

  @spec base(String.t()) :: map()
  def base(kind), do: %{"kind" => kind, "schema_version" => WotexContinuum.schema_version()}

  @spec envelope(term(), String.t()) :: term()
  def envelope(data, kind) when is_map(data) and not is_struct(data) do
    data
    |> put_default(:kind, "kind", kind)
    |> put_default(:schema_version, "schema_version", WotexContinuum.schema_version())
  end

  def envelope(data, _), do: data

  @spec exact(term(), term(), String.t(), atom()) :: :ok | {:error, Error.t()}
  def exact(value, value, _, _), do: :ok

  def exact(_, _, path, code),
    do: Error.error(code, :validation, path, "value does not match the contract")

  defp supported_schema(version) do
    if Version.match?(version, "~> 2.0"),
      do: :ok,
      else:
        Error.error(
          :unsupported_schema_version,
          :compatibility,
          "/schema_version",
          "schema version is not supported"
        )
  end

  defp put_default(data, atom_key, string_key, value) do
    if Map.has_key?(data, atom_key) or Map.has_key?(data, string_key),
      do: data,
      else: Map.put(data, atom_key, value)
  end
end
