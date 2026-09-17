ExUnit.start(exclude: [:interop, :hardware])
Code.require_file("support/client.ex", __DIR__)
Code.require_file("support/runtime_error_port.ex", __DIR__)
Code.require_file("support/runtime_client.ex", __DIR__)
Code.require_file("support/runtime_recording_transport.ex", __DIR__)
Code.require_file("support/native_fixture.ex", __DIR__)
Code.require_file("support/native_processes.ex", __DIR__)
Code.require_file("support/native_lane.ex", __DIR__)
Code.require_file("support/software_peer.ex", __DIR__)

if System.get_env("WOTEX_REQUIRE_SOFTWARE") == "1" do
  Wotex.BLE.SoftwarePeer.configure!()
  Code.require_file("support/software_formatter.ex", __DIR__)
  ExUnit.configure(formatters: [ExUnit.CLIFormatter, Wotex.BLE.SoftwareFormatter])
end
