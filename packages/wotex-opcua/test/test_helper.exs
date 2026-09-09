excluded =
  if System.get_env("WOTEX_REQUIRE_NATIVE_BUILD") == "1",
    do: [:interop, :hardware],
    else: [:interop, :hardware, :native_build]

ExUnit.start(exclude: excluded)
Code.require_file("support/client.ex", __DIR__)
