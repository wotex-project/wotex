ExUnit.start(exclude: [:interop, :hardware])
Code.require_file("support/client.ex", __DIR__)
Code.require_file("support/segment_transport.ex", __DIR__)
Code.require_file("support/blocking_client.ex", __DIR__)
