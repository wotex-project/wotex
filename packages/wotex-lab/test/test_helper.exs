broker = if System.get_env("WOTEX_LAB_BROKER") == "1", do: [], else: [broker: true]
maude = if System.get_env("WOTEX_LAB_MAUDE"), do: [], else: [maude: true]
greptime = if System.get_env("WOTEX_LAB_GREPTIME") == "1", do: [], else: [greptime: true]

integration =
  if System.get_env("WOTEX_LAB_INTEGRATION") == "1", do: [], else: [integration: true]

ExUnit.start(exclude: broker ++ maude ++ greptime ++ integration)
