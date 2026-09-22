defmodule WotexLabStorybook.Stories.Islands do
  use PhoenixStorybook.Story, :live_component

  alias PhoenixStorybook.Stories.{Attr, Variation}

  @spec component() :: module()
  def component, do: WotexLabStorybookWeb.IslandLive

  @spec attributes() :: [Attr.t()]
  def attributes do
    [
      %Attr{
        id: :fixture_id,
        type: :string,
        required: true,
        doc: "Stable Wotex Lab fixture identity"
      },
      %Attr{id: :revision, type: :integer, default: 1, doc: "Server-owned snapshot revision"}
    ]
  end

  @spec variations() :: [Variation.t()]
  def variations do
    [
      %Variation{
        id: :reporting_chart,
        description: "Chart island with a figure and table fallback",
        attributes: %{fixture_id: "reporting-chart"}
      },
      %Variation{
        id: :data_grid,
        description: "Keyboard data grid with a semantic table fallback",
        attributes: %{fixture_id: "data-grid"}
      },
      %Variation{
        id: :navigation_tabs,
        description: "Tabs with all sections retained as fallback content",
        attributes: %{fixture_id: "navigation-tabs"}
      }
    ]
  end
end
