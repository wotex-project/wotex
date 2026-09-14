defmodule Wotex.Nx.DataSchemaContract do
  @moduledoc false

  alias Wotex.DataSchema

  @spec valid?(term()) :: boolean()
  def valid?(%DataSchema{} = schema) do
    DataSchema.new(DataSchema.to_map(schema)) == {:ok, schema}
  rescue
    _ in [ArgumentError, FunctionClauseError] -> false
  end

  def valid?(_), do: false
end
