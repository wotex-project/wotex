defmodule Wotex.Workspace.Report do
  @moduledoc """
  Plain-text summary tables for the workspace tasks.
  """

  @type row :: %{
          optional(:package) => String.t(),
          optional(:step) => String.t(),
          optional(:gate) => String.t(),
          result: String.t(),
          seconds: number()
        }

  @doc """
  Renders rows as an aligned table. `columns` names the row keys to show, in
  order; it defaults to `package | result | seconds`. A `:seconds` column is
  formatted with one decimal.
  """
  @spec table([row()], [atom()]) :: String.t()
  def table(rows, columns \\ [:package, :result, :seconds]) do
    cells = [Enum.map(columns, &Atom.to_string/1) | Enum.map(rows, &cells(&1, columns))]

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

  defp cells(row, columns) do
    Enum.map(columns, fn
      :seconds -> seconds(row.seconds)
      column -> to_string(Map.get(row, column, ""))
    end)
  end

  defp format_row(cells, widths) do
    cells
    |> Enum.zip(widths)
    |> Enum.map_join(" | ", fn {cell, width} -> String.pad_trailing(cell, width) end)
    |> String.trim_trailing()
  end
end
