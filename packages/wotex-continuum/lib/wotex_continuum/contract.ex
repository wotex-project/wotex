defmodule WotexContinuum.Contract do
  @moduledoc false

  alias WotexContinuum.{Error, Validation}

  @spec normalize(map(), [atom()], String.t()) :: {:ok, map()} | {:error, Error.t()}
  def normalize(data, fields, expected_kind) do
    with {:ok, data} <- Validation.normalize(data, [:kind, :schema_version | fields]),
         {:ok, kind} <- Validation.required(data, :kind),
         {:ok, kind} <- Validation.string(kind, ["kind"], max: 128),
         :ok <- exact(kind, expected_kind, ["kind"], :wrong_kind),
         {:ok, schema_version} <- Validation.required(data, :schema_version),
         {:ok, schema_version} <- Validation.semver(schema_version, ["schema_version"]),
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

  def envelope(data, _kind), do: data

  @spec exact(term(), term(), [Error.segment()], atom()) :: :ok | {:error, Error.t()}
  def exact(value, value, _path, _code), do: :ok

  def exact(_value, _expected, path, code),
    do: Error.error(code, path, "value does not match the contract")

  defp supported_schema(version) do
    if Version.match?(version, "~> 1.0"),
      do: :ok,
      else:
        Error.error(
          :unsupported_schema_version,
          ["schema_version"],
          "schema version is not supported"
        )
  end

  defp put_default(data, atom_key, string_key, value) do
    if Map.has_key?(data, atom_key) or Map.has_key?(data, string_key),
      do: data,
      else: Map.put(data, atom_key, value)
  end
end
