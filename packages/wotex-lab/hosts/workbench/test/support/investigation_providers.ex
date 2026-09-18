defmodule WotexLabWorkbench.FakeCodexRunner do
  @moduledoc false

  @doc false
  @spec complete([map()], keyword()) :: term()
  def complete(_, _) do
    Application.get_env(
      :wotex_lab_workbench,
      :fake_codex_result,
      {:ok, "codex diagnosis",
       %{provider: :codex, model: "test-codex", plan_type: "pro", quota: %{used_percent: 1}}}
    )
  end

  @doc false
  @spec preflight() :: term()
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

  @doc false
  @spec complete([map()], keyword()) :: term()
  def complete(_, _) do
    Application.get_env(
      :wotex_lab_workbench,
      :fake_ollama_result,
      {:ok, "ollama diagnosis", %{provider: :ollama, model: "test-ollama"}}
    )
  end

  @doc false
  @spec preflight() :: term()
  def preflight do
    Application.get_env(
      :wotex_lab_workbench,
      :fake_ollama_preflight,
      {:ok, %{model: "test-ollama"}}
    )
  end
end

defmodule WotexLabWorkbench.FakeInvestigationRunner do
  @moduledoc false

  alias WotexLabWorkbench.Investigation.ContextStore

  @doc false
  @spec run(pid(), String.t(), pos_integer()) :: term()
  def run(_, prompt, _) do
    if owner = Application.get_env(:wotex_lab_workbench, :fake_investigation_owner) do
      send(owner, {:fake_investigation_started, self(), prompt})

      send(owner, {
        :fake_investigation_context,
        ContextStore.get("current"),
        ContextStore.get("baseline")
      })
    end

    # A zero-arity function is a scripted agent: it runs in the worker, so its
    # skill callbacks are charged and recorded like a real operator's calls.
    case Application.get_env(:wotex_lab_workbench, :fake_investigation_result, :block) do
      :block -> receive do: (:finish -> {:ok, []})
      script when is_function(script, 0) -> script.()
      result -> result
    end
  end
end
