defmodule WotexLabWorkbench.InvestigationDisclosureTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias WotexLabWorkbench.Investigation.Disclosure
  alias WotexLabWorkbenchWeb.Components.PromptComposer

  @local "http://127.0.0.1:11434/v1"

  test "a cloud-first selection states that bounded investigation data leaves the host" do
    disclosure = Disclosure.for_selection(:codex_then_ollama, @local)

    assert %{available: true, leaves_host: true} = disclosure

    assert disclosure.destinations == [
             "Codex service through the signed-in ChatGPT-plan account, attempted first",
             "Ollama on this host at 127.0.0.1:11434, used if Codex is unavailable"
           ]

    assert length(disclosure.sent) == 5
    assert Enum.any?(disclosure.sent, &(&1 =~ "node name, operating system, uptime"))
    assert Enum.any?(disclosure.sent, &(&1 =~ "at most 8 KiB"))
    assert disclosure.withheld =~ "Credentials, session and room tokens"

    html = render(disclosure)
    assert html =~ ~s(id="investigation-disclosure")
    assert html =~ "Data leaves this host"
    assert html =~ "Codex service through the signed-in ChatGPT-plan account"
    assert html =~ "other sessions&#39; data are not sent."
  end

  test "local Ollama stays on the host only for a loopback endpoint" do
    assert %{available: true, leaves_host: false, destinations: [destination]} =
             Disclosure.for_selection(:ollama, @local)

    assert destination == "Ollama on this host at 127.0.0.1:11434"
    assert render(Disclosure.for_selection(:ollama, @local)) =~ "Data stays on this host"

    remote = Disclosure.for_selection(:ollama, "https://models.example/v1")

    assert %{leaves_host: true, destinations: ["Ollama at models.example, outside this host"]} =
             remote

    assert render(remote) =~ "Data leaves this host"

    assert %{leaves_host: true, destinations: ["an unconfigured Ollama endpoint"]} =
             Disclosure.for_selection(:ollama, nil)

    assert %{leaves_host: true} = Disclosure.for_selection(:ollama, "http://10.0.0.8:11434/v1")
  end

  test "no provider selection discloses nothing and the configured selection is read at call time" do
    assert %{available: false, destinations: [], sent: []} = Disclosure.for_selection(:none, @local)
    refute render(Disclosure.for_selection(:none, @local)) =~ "investigation-disclosure"
    refute render(nil) =~ "investigation-disclosure"

    original = Application.get_env(:wotex_lab_workbench, :beamlens_provider)

    try do
      Application.put_env(:wotex_lab_workbench, :beamlens_provider, :codex_then_ollama)
      assert %{available: true, leaves_host: true} = Disclosure.current()
      Application.put_env(:wotex_lab_workbench, :beamlens_provider, :ollama)
      assert %{available: true, leaves_host: false} = Disclosure.current()
    after
      Application.put_env(:wotex_lab_workbench, :beamlens_provider, original)
    end

    assert Disclosure.current().available == false
  end

  defp render(disclosure) do
    %{disclosure: disclosure, disabled: false, running: false, value: "", reason: "ready"}
    |> PromptComposer.prompt_composer()
    |> rendered_to_string()
  end
end
