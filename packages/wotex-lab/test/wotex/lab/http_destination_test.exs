defmodule Wotex.Lab.HttpDestinationTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Binding.HTTP.{Request, Response}
  alias Wotex.Lab.Adapters.HTTP.ReqClient
  alias Wotex.Lab.Network.Destination
  alias Wotex.Lab.Test.HttpServer

  @moduletag capture_log: true

  test "the hosted profile rejects local, metadata, multicast and mixed DNS answers" do
    for address <- [
          {0, 0, 0, 0},
          {10, 0, 0, 1},
          {100, 64, 0, 1},
          {127, 0, 0, 1},
          {169, 254, 169, 254},
          {172, 16, 0, 1},
          {192, 168, 0, 1},
          {224, 0, 0, 1},
          {0, 0, 0, 0, 0, 0, 0, 1},
          {0xFC00, 0, 0, 0, 0, 0, 0, 1},
          {0xFE80, 0, 0, 0, 0, 0, 0, 1},
          {0xFF02, 0, 0, 0, 0, 0, 0, 1}
        ] do
      refute Destination.public_address?(address)
    end

    assert Destination.public_address?({8, 8, 8, 8})
    assert Destination.public_address?({0x2606, 0x4700, 0x4700, 0, 0, 0, 0, 0x1111})

    mixed = resolver(inet: [{93, 184, 216, 34}], inet6: [{0, 0, 0, 0, 0, 0, 0, 1}])

    assert {:error, :destination_not_admitted} =
             Destination.admit(
               "https://example.com/value",
               hosted_config(mixed)
             )
  end

  test "the hosted profile binds audience, HTTPS identity and the resolved peer" do
    public = resolver(inet: [{93, 184, 216, 34}], inet6: [])

    assert {:ok, admission} =
             Destination.admit("https://example.com/a?b=1", hosted_config(public))

    assert admission.origin == "https://example.com"
    assert admission.peer == {93, 184, 216, 34}
    assert admission.url == "https://93.184.216.34/a?b=1"
    assert admission.connect_options[:hostname] == "example.com"
    assert admission.connect_options[:transport_opts][:verify] == :verify_peer

    assert {:error, :destination_not_admitted} =
             Destination.admit(
               "https://other.example/value",
               hosted_config(public)
             )

    assert {:error, :destination_not_admitted} =
             Destination.admit(
               "http://example.com/value",
               hosted_config(public)
             )
  end

  test "local HTTPS verifies the fixture CA and the requested hostname" do
    fixture = Path.expand("../../fixtures/tls", __DIR__)
    ca_certfile = Path.join(fixture, "ca-cert.pem")
    certfile = Path.join(fixture, "localhost-cert.pem")
    keyfile = Path.join(fixture, "localhost-key.pem")

    assert {:ok, server} =
             HttpServer.start(self(), scheme: :https, certfile: certfile, keyfile: keyfile)

    on_exit(fn -> stop_server(server.server) end)

    assert {:ok, trusted} = request("https://localhost:#{server.port}/properties/temperature")

    assert {:ok, %Response{status: 200, body: "21.5"}} =
             ReqClient.request(trusted, nil, tls_ca_certfile: ca_certfile)

    assert {:ok, wrong_name} =
             request("https://127.0.0.1:#{server.port}/properties/temperature")

    assert {:error, :transport_failed} =
             ReqClient.request(wrong_name, nil, tls_ca_certfile: ca_certfile)

    private = resolver(inet: [{127, 0, 0, 1}], inet6: [])

    assert {:error, :destination_not_admitted} =
             ReqClient.request(trusted, {:bearer, "must-not-connect"},
               profile: :hosted,
               audience: "https://localhost:#{server.port}",
               resolver: private,
               tls_ca_certfile: ca_certfile
             )
  end

  test "client configuration is closed and bounded before a request" do
    assert {:ok, request} = request("http://127.0.0.1:1/value")

    for config <- [
          :invalid,
          [unknown: true],
          [receive_timeout: 0],
          [connect_timeout: 60_001],
          [profile: :hosted, audience: "https://example.com", finch: :shared],
          [resolver: :not_a_function]
        ] do
      assert {:error, :invalid_config} = ReqClient.request(request, nil, config)
    end
  end

  defp request(uri) do
    Request.new("GET", uri, [{"accept", "application/json"}], nil,
      request_id: "destination-test",
      operation: :readproperty,
      media_type: "application/json",
      stream?: false,
      deadline: nil,
      max_response_bytes: 1_024,
      max_event_bytes: 64
    )
  end

  defp hosted_config(resolver) do
    %{
      profile: :hosted,
      audience: "https://example.com",
      resolver: resolver,
      connect_timeout: 1_000,
      tls_ca_certfile: nil
    }
  end

  defp resolver(answers) do
    fn _, family -> {:ok, Keyword.get(answers, family, [])} end
  end

  defp stop_server(server) do
    if Process.alive?(server), do: Supervisor.stop(server)
  catch
    :exit, _ -> :ok
  end
end
