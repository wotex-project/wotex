defmodule Wotex.Workspace.Report do
  @moduledoc """
  Plain-text summary tables for the workspace tasks.
  """

  @type row :: %{package: String.t(), result: String.t(), seconds: number()}

  @doc """
  Renders `package | result | seconds` rows as an aligned table.
  """
  @spec table([row()]) :: String.t()
  def table(rows) do
    cells =
      [
        ["package", "result", "seconds"]
        | Enum.map(rows, &[&1.package, &1.result, seconds(&1.seconds)])
      ]

    widths =
      cells
      |> Enum.zip_with(fn column -> Enum.max(Enum.map(column, &String.length/1)) end)

    [header | body] = Enum.map(cells, &format_row(&1, widths))
    rule = widths |> Enum.map_join("-+-", &String.duplicate("-", &1))

    Enum.join([header, rule | body], "\n") <> "\n"
  end

  @doc "Formats elapsed seconds with one decimal."
  @spec seconds(number()) :: String.t()
  def seconds(value), do: :erlang.float_to_binary(value / 1, decimals: 1)

  defp format_row(cells, widths) do
    cells
    |> Enum.zip(widths)
    |> Enum.map_join(" | ", fn {cell, width} -> String.pad_trailing(cell, width) end)
    |> String.trim_trailing()
  end
end
