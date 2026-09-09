ExUnit.start(exclude: [:interop, :hardware, :software, :peer_shutdown])
Code.require_file("support/client.ex", __DIR__)
Code.require_file("support/segment_transport.ex", __DIR__)
Code.require_file("support/blocking_client.ex", __DIR__)
Code.require_file("support/cov_fault_client.ex", __DIR__)
Code.require_file("support/cov_port.ex", __DIR__)
Code.require_file("support/health_port.ex", __DIR__)
Code.require_file("support/runtime_credentials.ex", __DIR__)
Code.require_file("support/runtime_client.ex", __DIR__)
Code.require_file("support/native_helpers_client.ex", __DIR__)
Code.require_file("support/discovery_clock.ex", __DIR__)
Code.require_file("support/discovery_peer.ex", __DIR__)
Code.require_file("support/integration_client.ex", __DIR__)
Code.require_file("support/integration_transport.ex", __DIR__)
Code.require_file("support/cstack_peer.ex", __DIR__)

if System.get_env("WOTEX_REQUIRE_SOFTWARE") == "1" do
  Code.require_file("support/software_formatter.ex", __DIR__)
  ExUnit.configure(formatters: [ExUnit.CLIFormatter, Wotex.BACnet.SoftwareFormatter])

  for name <- ["WOTEX_BACNET_INTEROP_PORT", "WOTEX_BACNET_CONTROL_PORT"] do
    port = String.to_integer(System.fetch_env!(name))
    true = port in 1..65_535
  end

  for name <- ["WOTEX_BACNET_RESULTS_DIR", "WOTEX_BACNET_SOFTWARE_WORKSPACE"] do
    directory = System.fetch_env!(name)
    :absolute = Path.type(directory)
    true = File.dir?(directory)
  end
end
