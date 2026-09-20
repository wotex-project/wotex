defmodule WotexLabStorybook.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_, _) do
    children = [
      {Phoenix.PubSub, name: WotexLabStorybook.PubSub},
      WotexLabStorybookWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: WotexLabStorybook.Supervisor)
  end

  @impl Application
  def config_change(changed, removed, _) do
    WotexLabStorybookWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
