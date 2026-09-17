grafana = if System.get_env("WOTEX_LAB_GRAFANA") == "1", do: [], else: [grafana: true]

ExUnit.start(exclude: grafana)
