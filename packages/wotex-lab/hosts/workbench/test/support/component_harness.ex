defmodule WotexLabWorkbenchWeb.ComponentHarness do
  @moduledoc false

  use Phoenix.Component

  import WotexLabWorkbenchWeb.Components.AnswerBlock
  import WotexLabWorkbenchWeb.Components.Button
  import WotexLabWorkbenchWeb.Components.ContextHeader
  import WotexLabWorkbenchWeb.Components.DataTable
  import WotexLabWorkbenchWeb.Components.EmptyState
  import WotexLabWorkbenchWeb.Components.EvidenceLink
  import WotexLabWorkbenchWeb.Components.Field
  import WotexLabWorkbenchWeb.Components.MetricPanel
  import WotexLabWorkbenchWeb.Components.PromptComposer
  import WotexLabWorkbenchWeb.Components.StatusBadge
  import WotexLabWorkbenchWeb.Components.Tabs

  @doc false
  def render(assigns) do
    assigns =
      assigns
      |> assign(:rows, [%{value: "one"}])
      |> assign(:answer, %{status: "ok", text: "Observed", sources: []})

    ~H"""
    <.button>Run</.button>
    <.icon_button label="Open menu" icon={:menu} />
    <.context_header items={[{"state", "ready"}]} />
    <.field id="name" name="name" label="Name" help="Bounded" />
    <.tabs id="views" active="one">
      <:tab id="one" label="One">Panel one</:tab>
    </.tabs>
    <.status_badge status="failed" kind={:danger} />
    <.empty_state title="Empty">
      <:action>Continue</:action>
    </.empty_state>
    <.error_state title="Denied" code="denied" />
    <.data_table id="rows" caption="Rows" rows={@rows}>
      <:col :let={row} label="Value">{row.value}</:col>
    </.data_table>
    <.metric_panel title="Latency" value={nil} />
    <.evidence_link href="/evidence" label="Evidence" digest="sha256:abc" />
    <.prompt_composer />
    <.answer_block answer={@answer} />
    """
  end
end
