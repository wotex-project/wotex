defmodule WotexLabWorkbench.InvestigationCompletionControllerTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias WotexLabWorkbench.Investigation.Broker
  alias WotexLabWorkbench.Observability.Supervisor
  alias WotexLabWorkbenchWeb.InvestigationCompletionController

  @capability "ccccccccccccccccccccccccccccccccccccccccccc"
  @registry %{
    primary: "Test",
    clients: [
      %{
        name: "Test",
        provider: "openai-generic",
        options: %{
          api_key: @capability,
          base_url: "http://127.0.0.1:1/v1",
          model: "test"
        }
      }
    ]
  }

  setup do
    saved = Application.get_env(:wotex_lab_workbench, :beamlens_enabled)
    saved_provider = Application.get_env(:wotex_lab_workbench, :beamlens_provider)
    Application.put_env(:wotex_lab_workbench, :beamlens_provider, :codex_then_ollama)

    Application.put_env(
      :wotex_lab_workbench,
      :beamlens_operator_runner,
      WotexLabWorkbench.FakeInvestigationRunner
    )

    Application.put_env(:wotex_lab_workbench, :fake_investigation_owner, self())
    Application.put_env(:wotex_lab_workbench, :fake_investigation_result, :block)

    Application.put_env(
      :wotex_lab_workbench,
      :beamlens_codex_runner,
      WotexLabWorkbench.FakeCodexRunner
    )

    Application.put_env(
      :wotex_lab_workbench,
      :beamlens_ollama_runner,
      WotexLabWorkbench.FakeOllamaRunner
    )

    on_exit(fn ->
      restore(:beamlens_enabled, saved)
      restore(:beamlens_provider, saved_provider)

      for key <- [
            :beamlens_codex_runner,
            :beamlens_ollama_runner,
            :beamlens_operator_runner,
            :fake_investigation_owner,
            :fake_investigation_result,
            :fake_codex_result,
            :fake_ollama_result
          ],
          do: Application.delete_env(:wotex_lab_workbench, key)
    end)

    :ok
  end

  test "disabled and non-loopback requests cannot reach a provider" do
    conn = call(loopback_conn(), valid_params())
    assert conn.status == 403

    Application.put_env(:wotex_lab_workbench, :beamlens_enabled, true)
    conn = call(%{loopback_conn() | remote_ip: {203, 0, 113, 9}}, valid_params())
    assert conn.status == 403
  end

  test "one admitted loopback request returns an OpenAI-compatible result" do
    Application.put_env(:wotex_lab_workbench, :beamlens_enabled, true)
    activate_bridge()
    conn = call(loopback_conn(), valid_params())
    body = Jason.decode!(conn.resp_body)

    assert conn.status == 200
    assert get_in(body, ["choices", Access.at(0), "message", "content"]) == "codex diagnosis"
    assert body["model"] == "test-codex"
  end

  test "streaming, unknown models and oversized or malformed messages are refused" do
    Application.put_env(:wotex_lab_workbench, :beamlens_enabled, true)

    assert call(loopback_conn(), Map.put(valid_params(), "stream", true)).status == 403
    assert call(loopback_conn(), Map.put(valid_params(), "model", "other")).status == 403

    oversized = [%{"role" => "user", "content" => String.duplicate("x", 33 * 1_024)}]
    assert call(loopback_conn(), %{"messages" => oversized}).status == 422

    assert call(loopback_conn(), %{"messages" => [%{"role" => "tool", "content" => "x"}]}).status ==
             422
  end

  test "provider exhaustion is a service-unavailable result" do
    Application.put_env(:wotex_lab_workbench, :beamlens_enabled, true)
    activate_bridge()
    Application.put_env(:wotex_lab_workbench, :fake_codex_result, {:error, :codex_timeout})
    Application.put_env(:wotex_lab_workbench, :fake_ollama_result, {:error, :offline})

    assert call(loopback_conn(), valid_params()).status == 503
  end

  test "the bridge requires an active broker scope and enforces its call budget" do
    Application.put_env(:wotex_lab_workbench, :beamlens_enabled, true)
    assert call(loopback_conn(), valid_params()).status == 403

    {request, room} = activate_bridge()
    for _call <- 1..8, do: assert(call(loopback_conn(), valid_params()).status == 200)
    assert call(loopback_conn(), valid_params()).status == 403

    Process.exit(room, :kill)
    assert_receive {:investigation, ^request, {:error, :session_revoked}}, 1_000
    assert call(loopback_conn(), valid_params()).status == 403
  end

  defp loopback_conn do
    Plug.Test.conn(:post, "/api/internal/beamlens/v1/chat/completions")
    |> Map.put(:remote_ip, {127, 0, 0, 1})
    |> Plug.Conn.put_req_header("authorization", "Bearer #{@capability}")
  end

  defp valid_params do
    %{
      "model" => "wotex-lab-investigation",
      "messages" => [%{"role" => "user", "content" => "bounded evidence"}],
      "stream" => false
    }
  end

  defp call(conn, params), do: InvestigationCompletionController.create(conn, params)

  defp activate_bridge do
    start_supervised!(
      {Supervisor,
       history: [interval_ms: 60_000], beamlens: %{capability: @capability, registry: @registry}}
    )

    room = spawn(fn -> Process.sleep(:infinity) end)
    assert {:ok, request} = Broker.ask("authorize bridge", room: room)
    assert_receive {:fake_investigation_started, _worker, "authorize bridge"}, 1_000
    {request, room}
  end

  defp restore(key, nil), do: Application.delete_env(:wotex_lab_workbench, key)
  defp restore(key, value), do: Application.put_env(:wotex_lab_workbench, key, value)
end
