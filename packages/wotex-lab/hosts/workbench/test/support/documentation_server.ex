defmodule WotexLabWorkbench.Test.DocumentationServer do
  @moduledoc false

  @behaviour Plug

  @impl Plug
  def init(directory) do
    %{
      directory: directory,
      static:
        Plug.Static.init(
          at: "/",
          from: directory,
          content_types: %{"pagefind" => "application/wasm"}
        )
    }
  end

  @impl Plug
  def call(conn, options) do
    conn = Plug.Conn.put_resp_header(conn, "cache-control", "no-store")

    conn =
      if String.ends_with?(conn.request_path, "/"),
        do: %{conn | path_info: List.insert_at(conn.path_info, -1, "index.html")},
        else: conn

    conn = Plug.Static.call(conn, options.static)

    if conn.halted do
      conn
    else
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_file(404, Path.join(options.directory, "404.html"))
    end
  end
end
