e2e = if System.get_env("WOTEX_LAB_E2E") == "1", do: [], else: [e2e: true]
ExUnit.start(exclude: e2e)

if System.get_env("WOTEX_LAB_E2E") == "1" do
  {:ok, {_, port}} = WotexLabStorybookWeb.Endpoint.server_info(:http)
  Application.put_env(:phoenix_test, :base_url, "http://127.0.0.1:#{port}")
  {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
end
