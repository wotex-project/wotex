ExUnit.start(exclude: [:interop, :hardware, :software])
Code.require_file("support/peer.ex", __DIR__)
Code.require_file("support/contract_fixture.ex", __DIR__)

Code.require_file("support/session_trace.ex", __DIR__)

Code.require_file("support/runtime_credentials.ex", __DIR__)
Code.require_file("support/runtime_transport.ex", __DIR__)
Code.require_file("support/runtime_fixture.ex", __DIR__)

if System.get_env("WOTEX_REQUIRE_SOFTWARE") == "1" do
  "127.0.0.1" = System.fetch_env!("WOTEX_MODBUS_INTEROP_HOST")
  port = String.to_integer(System.fetch_env!("WOTEX_MODBUS_INTEROP_PORT"))
  true = port in 1..65_535
  evidence = System.fetch_env!("WOTEX_MODBUS_SOFTWARE_EVIDENCE")
  :absolute = Path.type(evidence)
  true = File.dir?(evidence)
end
