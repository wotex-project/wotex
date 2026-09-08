defmodule WotexLabWorkbenchWeb.Components do
  @moduledoc """
  The HEEx component family of the workbench.

  Every component uses semantic token roles (`--wl-*` variables from
  `Wotex.Lab.DesignSystem`), documented attributes and slots, and renders
  through HEEx escaping only. Status is always conveyed in text. A consumer
  overrides a component by rendering its own in the same slot, and overrides
  tokens through the host's `:token_overrides` configuration.

  | Module | Component |
  | --- | --- |
  | `WotexLabWorkbenchWeb.Components.Shell` | `shell/1`: sidebar, skip link, landmarks, theme |
  | `WotexLabWorkbenchWeb.Components.ContextHeader` | `context_header/1` |
  | `WotexLabWorkbenchWeb.Components.Button` | `button/1`, `icon_button/1` |
  | `WotexLabWorkbenchWeb.Components.Field` | `field/1` (text, number, select, textarea) |
  | `WotexLabWorkbenchWeb.Components.Tabs` | `tabs/1` |
  | `WotexLabWorkbenchWeb.Components.StatusBadge` | `status_badge/1` |
  | `WotexLabWorkbenchWeb.Components.EmptyState` | `empty_state/1`, `error_state/1` |
  | `WotexLabWorkbenchWeb.Components.DataTable` | `data_table/1` |
  | `WotexLabWorkbenchWeb.Components.MetricPanel` | `metric_panel/1` |
  | `WotexLabWorkbenchWeb.Components.Chart` | `chart/1` with table alternative |
  | `WotexLabWorkbenchWeb.Components.TensorSummary` | `tensor_summary/1` |
  | `WotexLabWorkbenchWeb.Components.EvidenceLink` | `evidence_link/1` |
  | `WotexLabWorkbenchWeb.Components.PromptComposer` | `prompt_composer/1` |
  | `WotexLabWorkbenchWeb.Components.AnswerBlock` | `answer_block/1` |
  | `WotexLabWorkbenchWeb.Components.ActionApproval` | `action_approval/1` |
  """

  @doc "The component modules, in shell order."
  @spec modules() :: [module()]
  def modules do
    [
      WotexLabWorkbenchWeb.Components.Shell,
      WotexLabWorkbenchWeb.Components.ContextHeader,
      WotexLabWorkbenchWeb.Components.Button,
      WotexLabWorkbenchWeb.Components.Field,
      WotexLabWorkbenchWeb.Components.Tabs,
      WotexLabWorkbenchWeb.Components.StatusBadge,
      WotexLabWorkbenchWeb.Components.EmptyState,
      WotexLabWorkbenchWeb.Components.DataTable,
      WotexLabWorkbenchWeb.Components.MetricPanel,
      WotexLabWorkbenchWeb.Components.Chart,
      WotexLabWorkbenchWeb.Components.TensorSummary,
      WotexLabWorkbenchWeb.Components.EvidenceLink,
      WotexLabWorkbenchWeb.Components.PromptComposer,
      WotexLabWorkbenchWeb.Components.AnswerBlock,
      WotexLabWorkbenchWeb.Components.ActionApproval
    ]
  end
end
