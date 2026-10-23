Code.require_file("../bin/support/documentation_browser_fixture.exs", __DIR__)
Code.require_file("../../../test/support/child_environment.ex", __DIR__)
Code.require_file("../../../test/support/modbus_simulator.ex", __DIR__)

grafana = if System.get_env("WOTEX_LAB_GRAFANA") == "1", do: [], else: [grafana: true]
greptime = if System.get_env("WOTEX_LAB_GREPTIME") == "1", do: [], else: [greptime: true]
e2e = if System.get_env("WOTEX_LAB_E2E") == "1", do: [], else: [e2e: true]

simulators = if System.get_env("WOTEX_LAB_SIMULATORS") == "1", do: [], else: [simulator: true]

documentation =
  if System.get_env("WOTEX_LAB_DOCUMENTATION") == "1", do: [], else: [documentation: true]

ExUnit.start(exclude: grafana ++ greptime ++ e2e ++ simulators ++ documentation)

if System.get_env("WOTEX_LAB_E2E") == "1" do
  {:ok, {_, port}} = WotexLabWorkbenchWeb.Endpoint.server_info(:http)
  Application.put_env(:phoenix_test, :base_url, "http://127.0.0.1:#{port}")
  {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
end
