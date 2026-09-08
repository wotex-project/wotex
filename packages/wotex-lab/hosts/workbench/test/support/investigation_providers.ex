defmodule WotexLabWorkbench.FakeCodexRunner do
  @moduledoc false

  def complete(_messages, _opts) do
    Application.get_env(
      :wotex_lab_workbench,
      :fake_codex_result,
      {:ok, "codex diagnosis",
       %{provider: :codex, model: "test-codex", plan_type: "pro", quota: %{used_percent: 1}}}
    )
  end

  def preflight do
    Application.get_env(
      :wotex_lab_workbench,
      :fake_codex_preflight,
      {:ok, %{plan_type: "pro", quota: %{used_percent: 1}}}
    )
  end
end

defmodule WotexLabWorkbench.FakeOllamaRunner do
  @moduledoc false

  def complete(_messages, _opts) do
    Application.get_env(
      :wotex_lab_workbench,
      :fake_ollama_result,
      {:ok, "ollama diagnosis", %{provider: :ollama, model: "test-ollama"}}
    )
  end

  def preflight do
    Application.get_env(
      :wotex_lab_workbench,
      :fake_ollama_preflight,
      {:ok, %{model: "test-ollama"}}
    )
  end
end
