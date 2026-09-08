defmodule WotexLabWorkbenchWeb.Components.DataTable do
  @moduledoc "An accessible data table: caption, column headers and cell slots."

  use Phoenix.Component

  attr :id, :string, required: true
  attr :caption, :string, required: true
  attr :rows, :list, required: true
  attr :empty, :string, default: "No rows."

  slot :col, required: true do
    attr :label, :string, required: true
  end

  @doc "Renders the table, or the empty text when there are no rows."
  @spec data_table(map()) :: Phoenix.LiveView.Rendered.t()
  def data_table(assigns) do
    ~H"""
    <div class="wl-table-wrap">
      <table id={@id} class="wl-table">
        <caption>{@caption}</caption>
        <thead>
          <tr>
            <th :for={col <- @col} scope="col">{col.label}</th>
          </tr>
        </thead>
        <tbody>
          <tr :if={@rows == []}>
            <td colspan={length(@col)} class="wl-table-empty">{@empty}</td>
          </tr>
          <tr :for={row <- @rows}>
            <td :for={col <- @col}>{render_slot(col, row)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end
