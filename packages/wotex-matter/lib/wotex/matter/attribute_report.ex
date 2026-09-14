defmodule Wotex.Matter.AttributeReport do
  @moduledoc """
  A successful concrete attribute report.

  The value is one validated anonymous outer TLV element. `nil` DataVersion is
  distinct from version zero.
  """

  alias Wotex.Matter.{Address, Error, TLV}

  @enforce_keys [:path, :value, :data_version]
  defstruct [:path, :value, :data_version]

  @type t :: %__MODULE__{
          path: Address.t(),
          value: TLV.element(),
          data_version: non_neg_integer() | nil
        }

  @doc "Reconstructs and validates a concrete attribute report."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = report), do: new(Map.from_struct(report))

  def new(%{path: path, value: value, data_version: version} = report) when map_size(report) == 3 do
    with {:ok, path} <- Address.new(path),
         {:ok, value} <- TLV.validate_element(value),
         true <- is_nil(version) or (is_integer(version) and version in 0..0xFFFFFFFF) do
      {:ok, %__MODULE__{path: path, value: value, data_version: version}}
    else
      _ -> {:error, Error.new(:invalid_attribute_report)}
    end
  end

  def new(_), do: {:error, Error.new(:invalid_attribute_report)}
end
