exclude =
  [broker: System.get_env("WOTEX_LAB_BROKER") != "1"] ++
    [greptime: System.get_env("WOTEX_LAB_GREPTIME") != "1"]

ExUnit.start(exclude: for({tag, true} <- exclude, do: {tag, true}))
