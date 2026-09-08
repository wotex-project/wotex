defmodule WotexLabNerves.Application do
  @moduledoc """
  Explicit supervision for the Raspberry Pi 4 reference firmware.

  Boot starts one bounded Lab instance but no experiment, network client,
  simulated Thing or physical effect. The on-target smoke remains an explicit
  operator call to `WotexLabNerves.Smoke.run/0`.
  """

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      Wotex.Lab.child_spec(
        id: "nerves-rpi4",
        name: WotexLabNerves.Lab,
        max_children: 8
      )
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: WotexLabNerves.Supervisor)
  end
end
