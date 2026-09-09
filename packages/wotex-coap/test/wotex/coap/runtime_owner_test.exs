defmodule Wotex.CoAP.RuntimeOwnerTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.CoAP.{Error, Message, RuntimeFrame, RuntimeNative, RuntimeRelay}

  test "WCO-C03 WCO-I05 native establishment owns its socket across the subscription handshake" do
    options = options(System.monotonic_time(:millisecond) + 100)
    generation = make_ref()
    {worker, monitor} = RuntimeNative.start(self(), generation, options)
    assert_receive {:runtime_session, ^generation, ^worker, session}
    assert RuntimeNative.valid_session?(session, worker, self(), options.connection_options)
    refute RuntimeNative.valid_session?(session, self(), worker, options.connection_options)
    refute RuntimeNative.valid_session?(%{pid: self(), timeout: 1}, worker, self(), [])
    refute RuntimeNative.valid_session?(nil, worker, self(), [])
    refute RuntimeNative.valid_subscription?(nil, nil)
    refute RuntimeNative.valid_subscription?(session, nil)
    state = :sys.get_state(session.pid)
    socket = :sys.get_state(state.handle.pid).socket

    assert_receive {:runtime_subscribed, ^generation, ^worker,
                    {:error, %Error{code: :deadline_exceeded}}},
                   200

    assert Process.alive?(worker) and Process.alive?(session.pid)
    assert :ok = RuntimeNative.close(session, nil, System.monotonic_time(:millisecond) + 100)
    send(worker, {:halt, generation})
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}
    assert :erlang.port_info(socket) == :undefined
    assert :ok = RuntimeNative.close(nil, nil, 0)
    assert :ok = RuntimeNative.abort(nil)
  end

  test "WCO-C02 WCO-I05 expired and invalid native setup returns bounded failures before acquisition" do
    for options <- [
          options(System.monotonic_time(:millisecond) - 1),
          %{
            options(System.monotonic_time(:millisecond) + 100)
            | connection_options: [host: "invalid"]
          }
        ] do
      generation = make_ref()
      {worker, monitor} = RuntimeNative.start(self(), generation, options)
      assert_receive {:runtime_subscribed, ^generation, ^worker, {:error, %Error{}}}
      refute_received {:runtime_session, ^generation, _, _}
      send(worker, {:halt, generation})
      assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}
    end

    assert {:error, %Error{code: :deadline_exceeded}} =
             RuntimeRelay.open(options(System.monotonic_time(:millisecond) - 1))

    assert {:error, %Error{code: :invalid_host}} =
             RuntimeRelay.open(%{
               options(System.monotonic_time(:millisecond) + 100)
               | connection_options: [host: "invalid"]
             })
  end

  test "WCO-C04 WCO-I05 Runtime frames validate complete representation metadata and bounded errors" do
    message = %Message{
      type: :non,
      code: 69,
      message_id: 1,
      token: "t",
      options: [{6, <<>>}, {12, <<42>>}],
      payload: <<255>>
    }

    metadata = %{code: 69, observe: 0, etag: nil, content_format: 42, max_age: 60}
    assert {:ok, <<255>>, ^metadata} = RuntimeFrame.decode(%{format: 42}, message, metadata)

    for {value, metadata} <- [
          {message, Map.put(metadata, :secret, "PRIVATE")},
          {%{message | options: [{23, <<8>>} | message.options]}, metadata},
          {Map.put(message, :extra, true), metadata},
          {message, %{metadata | observe: 1}},
          {%{message | payload: :binary.copy(<<0>>, 1_048_577)}, metadata}
        ] do
      assert {:error, %Error{code: :invalid_runtime_frame}} = RuntimeFrame.validate(value, metadata)
    end

    for value <- [
          nil,
          Error.new(:remote_response, nil, %{code: "PRIVATE"}),
          Error.new(:failed, nil, %{secret: "PRIVATE"}),
          Map.put(Error.new(:failed), :extra, true)
        ] do
      error = RuntimeFrame.error(value)
      assert error.code == :invalid_runtime_frame
      refute inspect(error) =~ "PRIVATE"
    end

    error = Error.new(:remote_response, nil, %{code: 132})
    assert RuntimeFrame.error(error) == error
  end

  defp options(deadline),
    do: %{
      owner: self(),
      path: "/x",
      renew: true,
      max_queue_length: 1000,
      connection_options: [host: "127.0.0.1"],
      deadline: deadline
    }
end
