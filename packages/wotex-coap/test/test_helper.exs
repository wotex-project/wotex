ExUnit.start(exclude: [:interop, :hardware])
Code.require_file("support/contract_fixture.ex", __DIR__)
Code.require_file("support/datagram.ex", __DIR__)

Code.require_file("support/execution.ex", __DIR__)

Code.require_file("support/observation_trace.ex", __DIR__)
