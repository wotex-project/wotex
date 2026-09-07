broker = if System.get_env("WOTEX_LAB_BROKER") == "1", do: [], else: [broker: true]
maude = if System.get_env("WOTEX_LAB_MAUDE"), do: [], else: [maude: true]

ExUnit.start(exclude: broker ++ maude)
