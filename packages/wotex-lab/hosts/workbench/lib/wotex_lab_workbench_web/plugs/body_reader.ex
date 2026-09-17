defmodule WotexLabWorkbenchWeb.Plugs.BodyReader do
  @moduledoc """
  The endpoint's request-body reader, which also counts the bytes it reads.

  `Plug.Parsers` calls `read_body/2` for every JSON or form body it parses. The
  reader delegates to `Plug.Conn.read_body/2`, keeps the parser's own length
  ceiling, and adds each chunk's size to the private
  `:wotex_lab_body_bytes` counter. The control API compares that counter with
  its smaller mutation ceiling, so a chunked request without `Content-Length`
  is measured exactly. The reader stores no body content.
  """

  @doc "Reads one body chunk and accumulates its byte size on the connection."
  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()} | {:error, term()}
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {status, chunk, conn} when status in [:ok, :more] ->
        read = Map.get(conn.private, :wotex_lab_body_bytes, 0) + byte_size(chunk)
        {status, chunk, Plug.Conn.put_private(conn, :wotex_lab_body_bytes, read)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "The number of body bytes read so far."
  @spec bytes(Plug.Conn.t()) :: non_neg_integer()
  def bytes(conn), do: Map.get(conn.private, :wotex_lab_body_bytes, 0)
end
