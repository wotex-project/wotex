defmodule Wotex.Routines.InputFixtures do
  @moduledoc false

  alias Wotex.Routines.{Basis, InputMapping}

  @spec vector() :: map()
  def vector do
    path = Path.expand("../../priv/vectors/wro-05-input.json", __DIR__)
    Jason.decode!(File.read!(path))
  end

  @spec context(map()) :: map()
  def context(v),
    do: %{
      "registry" => v["registry"],
      "limits" => v["limits"],
      "reader_limits" => v["reader_limits"]
    }

  @spec prepare(map(), map()) :: {map(), list()}
  def prepare(v, unsigned) do
    basis = unsigned["basis"]
    {:ok, digest} = Basis.semantic_digest(basis, v["limits"])
    basis = Map.put(basis, "semantic_digest", digest)
    basis_ref = Map.take(basis, ~w(id version semantic_digest))

    unsigned =
      unsigned
      |> Map.put("basis", basis)
      |> Map.put("legacy_basis_ref", basis_ref)

    registry =
      Enum.map(v["registry"], fn record ->
        record =
          if record["id"] == basis["id"],
            do: Map.put(record, "semantic_digest", digest),
            else: record

        Map.update!(record, "requires", fn refs ->
          Enum.map(refs, &replace_basis(&1, basis_ref))
        end)
      end)

    {unsigned, registry}
  end

  @spec install(map(), map()) :: map()
  def install(v, unsigned) do
    {unsigned, registry} = prepare(v, unsigned)
    {:ok, digest} = InputMapping.digest(unsigned, registry, v["limits"])
    mapping = Map.put(unsigned, "sha256", digest)
    basis_ref = unsigned["legacy_basis_ref"]

    registry =
      Enum.map(registry, fn record ->
        if record["id"] == mapping["id"] do
          record
          |> Map.put("semantic_digest", "sha256:" <> digest)
          |> Map.put("requires", [basis_ref])
        else
          record
        end
      end)

    v
    |> Map.put("mapping", mapping)
    |> Map.put("registry", registry)
  end

  defp replace_basis(ref, basis_ref) do
    if ref["id"] == basis_ref["id"], do: basis_ref, else: ref
  end
end
