defmodule WotexLabWorkbenchWeb.Components.DataTable do
  @moduledoc """
  Displays supplied rows using a caption and labelled column slots.

  Each column receives the current row and owns its cell rendering. An empty
  collection produces one explanatory row spanning the declared columns.
  Paging, sorting and row limits belong to the caller; this component renders
  the supplied collection without fetching or truncating it. Table ids must be
  unique within the surrounding page.
  """

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
