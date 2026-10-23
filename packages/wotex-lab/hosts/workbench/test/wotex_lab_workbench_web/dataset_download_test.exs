defmodule WotexLabWorkbenchWeb.DatasetDownloadTest do
  @moduledoc false

  use WotexLabWorkbenchWeb.ConnCase, async: false

  alias WotexLabWorkbench.{Metrics, Room, Sessions}
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

  test "a dataset attachment contains the full capture and can name only its current room", %{
    conn: conn
  } do
    {owner, session, dataset} = capture(conn)
    before = Room.snapshot(session.room)
    response = get(recycle(owner), "/evidence/datasets/dataset-1")
    decoded = json_response(response, 200)
    assert decoded["digest"] == dataset.digest
    assert decoded["rows"] == length(decoded["samples"])
    assert decoded["source"]["scope"] == session.id
    assert get_resp_header(response, "cache-control") == ["no-store"]

    assert get_resp_header(response, "content-disposition") == [
             ~s(attachment; filename="wotex-lab-dataset-1.json")
           ]

    assert Room.snapshot(session.room) == before

    empty = get(build_conn(), "/") |> track_session()
    assert response(get(recycle(empty), "/evidence/datasets/dataset-1"), 404)
    {other, other_session, other_dataset} = capture(build_conn())
    assert other_session.id != session.id
    other_response = get(recycle(other), "/evidence/datasets/dataset-1") |> json_response(200)
    assert other_response["digest"] == other_dataset.digest
    refute other_response["digest"] == dataset.digest
    assert other_response["source"]["scope"] == other_session.id

    assert response(get(recycle(owner), "/evidence/datasets/unknown"), 404)
    assert response(get(recycle(owner), "/evidence/datasets/dataset-1?scope=another"), 400)
    assert response(get(recycle(owner), "/evidence/datasets/" <> String.duplicate("x", 65)), 400)
    Sessions.revoke(session.token)
    assert response(get(recycle(owner), "/evidence/datasets/dataset-1"), 403)
  end

  defp capture(conn) do
    conn = get(conn, "/") |> track_session()
    token = get_session(conn, SessionToken.key())
    {:ok, session} = Sessions.admit(token, :start_room)
    Metrics.record(session.id, :scenario, :inference, %{duration: 12}, %{outcome: :ok})
    {:ok, dataset} = Room.export_dataset(session.room, [])
    {conn, session, dataset}
  end
end
