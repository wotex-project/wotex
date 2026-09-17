grafana = if System.get_env("WOTEX_LAB_GRAFANA") == "1", do: [], else: [grafana: true]
greptime = if System.get_env("WOTEX_LAB_GREPTIME") == "1", do: [], else: [greptime: true]

ExUnit.start(exclude: grafana ++ greptime)
