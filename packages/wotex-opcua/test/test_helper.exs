excluded =
  if System.get_env("WOTEX_REQUIRE_NATIVE_BUILD") == "1",
    do: [:interop, :hardware],
    else: [:interop, :hardware, :native_build]

ExUnit.start(exclude: excluded)
Code.require_file("support/client.ex", __DIR__)
Code.require_file("support/stream_client.ex", __DIR__)
Code.require_file("support/nosec_credentials.ex", __DIR__)
Code.require_file("support/failure_transport.ex", __DIR__)
