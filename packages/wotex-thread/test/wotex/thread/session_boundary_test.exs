defmodule Wotex.Thread.SessionBoundaryTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Thread
  alias Wotex.Thread.{Daemon, Error, Session, TestClient}

  @moduletag requirements: ["WTH-C02", "WTH-C03", "WTH-N01"]

  test "forged Sessions are rejected before custom client callbacks" do
    {:ok, session} = Thread.connect(client: TestClient)

    for forged <- [
          Map.put(session, :extra, true),
          %{session | timeout: 0},
          %{session | timeout: :infinity},
          %{session | client: nil},
          %{session | client: false},
          %{session | client: "untrusted"}
        ] do
      assert {:error, %Error{code: :invalid_session}} = Thread.send(forged, %{type: :state})
      assert {:error, %Error{code: :invalid_session}} = Thread.disconnect(forged)
      assert {:error, %Error{code: :invalid_session}} = Thread.inspect_state(forged, [])
    end

    refute_received :disconnected

    for invalid <- [nil, [], %{}] do
      assert {:error, %Error{code: :invalid_session}} = Session.validate(invalid)
      assert {:error, %Error{code: :invalid_session}} = Thread.disconnect(invalid)
      assert {:error, %Error{code: :invalid_session}} = Thread.inspect_state(invalid, [])
    end

    assert :ok = Thread.disconnect(session)
    assert_receive :disconnected
  end

  test "keyword duplicates and improper lists fail before selecting a client" do
    for options <- [
          [client: TestClient, client: TestClient],
          [{:client, TestClient} | :improper],
          [client: TestClient, timeout: 1, timeout: 2],
          [{"client", TestClient}],
          List.duplicate({:client, TestClient}, 100)
        ] do
      assert {:error, %Error{code: :invalid_options}} = Thread.connect(options)
    end

    assert {:error, %Error{code: :invalid_callback}} =
             Thread.with_connection([client: TestClient], nil)
  end

  test "native inspection rejects unsupported clients and options before socket or callback access" do
    for client <- [Daemon, TestClient] do
      session = %Session{client: client, handle: :unavailable, timeout: 1000}
      assert {:error, %Error{code: :not_supported}} = Thread.inspect_state(session, [])

      for options <- [
            [timeout: 0],
            [timeout: :infinity],
            [timeout: 1, timeout: 2],
            [{:timeout, 1000} | :improper],
            [unknown: true],
            %{},
            nil
          ] do
        assert {:error, %Error{code: :invalid_options}} = Thread.inspect_state(session, options)
      end
    end
  end
end
