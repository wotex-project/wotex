exclude = if System.get_env("WOTEX_LAB_BROKER") == "1", do: [], else: [broker: true]

ExUnit.start(exclude: exclude)
