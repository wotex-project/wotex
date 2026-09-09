defmodule WotexContinuum.Schema do
  @moduledoc """
  Embedded normative JSON Schemas and immutable identities.

  Schema bytes are embedded at compile time; fetching them performs no runtime
  filesystem operation.

  `ids/0` lists the registered WCT.01, WCT.02, and WCT.03 schema identifiers in
  lexical order. `fetch/1` returns the exact embedded bytes, and `info/1`
  reports their byte count, continuum schema version, and lowercase SHA-256
  digest. Unknown and malformed identifiers return `WotexContinuum.Error`.

  Embedding makes the schema identity independent of a runtime working
  directory. It does not make JSON Schema evaluation part of the module or
  replace the typed constructors. Consumers may use the bytes with a selected
  validator, while `WotexContinuum.from_map/1` remains the authoritative
  constructor boundary for package values.
  """

  alias WotexContinuum.Error

  @schema_paths %{
    "WCT.01" => "wct-01.schema.json",
    "WCT.02" => "wct-02.schema.json",
    "WCT.03" => "wct-03.schema.json"
  }

  @schemas Map.new(@schema_paths, fn {id, filename} ->
             path = Path.expand("../../priv/schemas/#{filename}", __DIR__)
             @external_resource path
             {id, File.read!(path)}
           end)

  @doc "Returns registered schema IDs in lexical order."
  @spec ids() :: [String.t()]
  def ids do
    @schemas
    |> Map.keys()
    |> Enum.sort()
  end

  @doc "Returns exact embedded JSON Schema bytes."
  @spec fetch(String.t()) :: {:ok, binary()} | {:error, Error.t()}
  def fetch(id) when is_binary(id) do
    case Map.fetch(@schemas, id) do
      {:ok, source} ->
        {:ok, source}

      :error ->
        Error.error(:unknown_schema, :validation, "/", "schema ID is not registered", %{id: id})
    end
  end

  def fetch(_), do: Error.error(:invalid_type, :validation, "/", "expected a schema ID string")

  @doc "Returns schema version, byte count, and lowercase SHA-256 identity."
  @spec info(String.t()) :: {:ok, map()} | {:error, Error.t()}
  def info(id) do
    with {:ok, source} <- fetch(id) do
      {:ok,
       %{
         id: id,
         schema_version: WotexContinuum.schema_version(),
         bytes: byte_size(source),
         digest: "sha256:" <> Base.encode16(:crypto.hash(:sha256, source), case: :lower)
       }}
    end
  end
end
