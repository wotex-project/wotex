defmodule WotexLabWorkbench.InvestigationProviderTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias WotexLabWorkbench.Investigation.{Deadline, Provider, Status}

  setup do
    start_supervised!(Status)

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
      for key <- [
            :beamlens_codex_runner,
            :beamlens_ollama_runner,
            :fake_codex_result,
            :fake_ollama_result,
            :fake_codex_preflight,
            :fake_ollama_preflight
          ],
          do: Application.delete_env(:wotex_lab_workbench, key)
    end)

    :ok
  end

  test "uses signed-in ChatGPT-plan Codex first" do
    assert {:ok, "codex diagnosis", %{provider: :codex, plan_type: "pro", reason: nil}} =
             Provider.complete([%{"role" => "user", "content" => "diagnose"}])
  end

  test "discloses a fixed local fallback when Codex is unavailable" do
    Application.put_env(:wotex_lab_workbench, :fake_codex_result, {:error, :codex_timeout})

    assert {:ok, "ollama diagnosis", %{provider: :ollama, reason: reason}} =
             Provider.complete([%{"role" => "user", "content" => "diagnose"}])

    assert reason =~ "timed out"
    assert Provider.status().provider == :ollama
  end

  test "reports distinct unavailability when both providers fail" do
    Application.put_env(
      :wotex_lab_workbench,
      :fake_codex_result,
      {:error, :chatgpt_login_required}
    )

    Application.put_env(
      :wotex_lab_workbench,
      :fake_ollama_result,
      {:error, :ollama_unavailable}
    )

    assert {:error, :diagnostics_unavailable} = Provider.complete([])
    assert %{state: :unavailable, reason: reason} = Provider.status()
    assert reason =~ "Codex"
    assert reason =~ "Ollama"
  end

  test "preflight does not consume a model turn" do
    Application.put_env(
      :wotex_lab_workbench,
      :fake_codex_preflight,
      {:error, :codex_not_installed}
    )

    assert %{available: true} = Provider.refresh_status()
    assert %{state: :available, provider: :ollama, reason: reason} = Provider.status()
    assert reason =~ "not installed"
  end

  test "deadline kills work and work dies when its caller exits" do
    parent = self()

    assert {:error, :timeout} =
             Deadline.run(
               fn ->
                 send(parent, {:worker, self()})
                 Process.sleep(:infinity)
               end,
               10
             )

    assert_receive {:worker, worker}
    refute Process.alive?(worker)

    caller =
      spawn(fn ->
        Deadline.run(
          fn ->
            send(parent, {:owned_worker, self()})
            Process.sleep(:infinity)
          end,
          10_000
        )
      end)

    assert_receive {:owned_worker, owned_worker}
    monitor = Process.monitor(owned_worker)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owned_worker, _reason}, 1_000
  end
end
