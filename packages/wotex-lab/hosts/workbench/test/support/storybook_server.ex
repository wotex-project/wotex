defmodule WotexLabWorkbench.Test.StorybookServer do
  @moduledoc false

  @behaviour Plug

  @impl Plug
  def init(directory), do: Plug.Static.init(at: "/", from: directory)

  @impl Plug
  def call(conn, options) do
    conn = Plug.Static.call(conn, options)
    if conn.halted, do: conn, else: Plug.Conn.send_resp(conn, 404, "Not found")
  end
end
