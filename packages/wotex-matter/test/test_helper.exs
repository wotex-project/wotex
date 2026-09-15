ExUnit.start(exclude: [:interop, :software, :hardware])

if System.get_env("WOTEX_REQUIRE_SOFTWARE") do
  Code.require_file("support/software/acceptance.exs", __DIR__)
  Wotex.Matter.SoftwareAcceptance.configure!(File.cwd!(), System.get_env())
end

Code.require_file("support/client.ex", __DIR__)
Code.require_file("support/catalogue_client.ex", __DIR__)
Code.require_file("support/runtime_client.ex", __DIR__)
Code.require_file("support/runtime_credentials.ex", __DIR__)
Code.require_file("support/runtime_result_transport.ex", __DIR__)
