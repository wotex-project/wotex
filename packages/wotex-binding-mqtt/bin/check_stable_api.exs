defmodule Wotex.Binding.MQTT.Check.StableAPI do
  @moduledoc false

  alias Wotex.Binding.MQTT

  alias Wotex.Binding.MQTT.{
    Broker,
    Client,
    Command,
    Delivery,
    Error,
    JSON,
    Mapping,
    QoS,
    Topic,
    Transport,
    TransportConfig
  }

  alias Wotex.Runtime.BindingProfile

  @operations [
    :readproperty,
    :writeproperty,
    :observeproperty,
    :unobserveproperty,
    :invokeaction,
    :subscribeevent,
    :unsubscribeevent
  ]

  @callable_surface %{
    MQTT => [profile: 0],
    Broker => [host: 1, href: 1, new: 1, port: 1, scheme: 1],
    Client => [],
    Command => [
      broker: 1,
      content_type: 1,
      filters: 1,
      max_payload_bytes: 1,
      operation: 1,
      packet: 1,
      payload: 1,
      publish: 4,
      publish: 5,
      qos: 1,
      retain?: 1,
      subscribe: 3,
      subscribe: 4,
      topic: 1,
      unsubscribe: 3,
      unsubscribe: 4
    ],
    Delivery => [new: 2, normalize: 1, payload: 1, qos: 1, retained?: 1, topic: 1],
    Error => [class: 1],
    JSON => [decode: 2, encode: 2],
    Mapping => [command: 2, default_control_packet: 1],
    QoS => [normalize: 1],
    Topic => [matches?: 2, normalize_filters: 1, validate_filter: 1, validate_name: 1],
    Transport => [decode_frame: 3, request: 3, subscribe: 4, unsubscribe: 4],
    TransportConfig => [max_payload_bytes: 1, new: 2, new: 3, read_timeout: 1]
  }

  @mechanics %{
    Broker => [__struct__: 0, __struct__: 1],
    Command => [__struct__: 0, __struct__: 1],
    Delivery => [__struct__: 0, __struct__: 1],
    Error => [
      __struct__: 0,
      __struct__: 1,
      exception: 1,
      message: 1,
      new: 4,
      new: 5
    ],
    TransportConfig => [__struct__: 0, __struct__: 1]
  }

  @callbacks [publish: 3, read: 4, subscribe: 4, unsubscribe: 4]

  @spec main() :: :ok
  def main do
    result =
      try do
        verify!()
      catch
        :throw, {:violation, message} -> {:violation, message}
      end

    report(result)
  end

  defp verify! do
    verify_surface!()
    verify_profile!()
    verify_inventory!()
    verify_error_manifest!()
    verify_catalogue!()
    verify_gate!()
    :ok
  end

  defp verify_surface! do
    Enum.each(@callable_surface, fn {module, expected} ->
      unless Code.ensure_loaded?(module),
        do: violation("stable module is unavailable: #{inspect(module)}")

      actual =
        module
        |> apply(:__info__, [:functions])
        |> Kernel.--(Map.get(@mechanics, module, []))
        |> Enum.sort()

      exact!(actual, Enum.sort(expected), "callable surface for #{inspect(module)}")
    end)

    actual_callbacks = Client.behaviour_info(:callbacks) |> Enum.sort()
    exact!(actual_callbacks, Enum.sort(@callbacks), "MQTT client callbacks")
  end

  defp verify_profile! do
    profile = MQTT.profile()
    exact!(BindingProfile.id(profile), :mqtt, "profile id")

    for scheme <- ["mqtt", "mqtts", "MQTT", "MQTTS"] do
      unless BindingProfile.supports_scheme?(profile, scheme) do
        violation("profile does not support #{inspect(scheme)}")
      end
    end

    if BindingProfile.supports_scheme?(profile, "http") do
      violation("profile unexpectedly supports HTTP")
    end

    for media_type <- ["application/json", "Application/JSON; charset=utf-8"] do
      unless BindingProfile.supports_media_type?(profile, media_type) do
        violation("profile does not support #{inspect(media_type)}")
      end
    end

    supported =
      Wotex.Runtime.operations()
      |> Enum.filter(&BindingProfile.supports_operation?(profile, &1))
      |> Enum.sort()

    exact!(supported, Enum.sort(@operations), "profile operations")
  end

  defp verify_inventory! do
    inventory = File.read!("docs/stable-api-inventory.md")

    for vector <- Enum.map(1..8, &"WBM-S0#{&1}") do
      require!(inventory, vector, "stable API inventory is missing #{vector}")
    end

    for value <- [
          "1,048,576",
          "5,000",
          "65,535",
          "256",
          "{:wotex_transport_frame, delivery}",
          "{:wotex_transport_status, status}",
          "new version plus a migration record",
          "never authority to silently"
        ] do
      require!(inventory, value, "stable API inventory is missing #{inspect(value)}")
    end

    for code <- [
          "invalid_broker_href",
          "too_many_topic_filters",
          "encoded_payload_too_large",
          "control_packet_mismatch",
          "invalid_transport_option",
          "deadline_exceeded",
          "client_publish_failed",
          "invalid_client_return",
          "delivery_topic_mismatch"
        ] do
      require!(inventory, code, "stable API inventory is missing error code #{code}")
    end
  end

  defp verify_catalogue! do
    catalogue = File.read!("docs/specs/catalogue.yaml")
    evidence = "test/wotex/binding/mqtt/stable_api_test.exs"

    unless File.regular?(evidence), do: violation("stable API executable evidence is missing")

    exact!(
      Regex.scan(~r/#{Regex.escape(evidence)}/, catalogue) |> length(),
      3,
      "stable API catalogue evidence count"
    )

    exact!(
      Regex.scan(~r/WBM-C06 stable 0\.1 candidate/, catalogue) |> length(),
      3,
      "stable API compatibility decisions"
    )
  end

  defp verify_error_manifest! do
    inventory = File.read!("docs/stable-api-inventory.md")

    manifest =
      section!(inventory, "<!-- error-manifest:start -->", "<!-- error-manifest:end -->")

    manifest_codes =
      ~r/`([a-z][a-z0-9_]+)`/
      |> Regex.scan(manifest, capture: :all_but_first)
      |> List.flatten()
      |> MapSet.new()

    source_codes =
      "lib/wotex/binding/mqtt/*.ex"
      |> Path.wildcard()
      |> Enum.reduce(MapSet.new(), fn file, codes ->
        file
        |> File.read!()
        |> Code.string_to_quoted!()
        |> collect_error_codes(codes)
      end)

    exact!(manifest_codes, source_codes, "stable binding error code manifest")
  end

  defp collect_error_codes(ast, initial) do
    {_ast, codes} =
      Macro.prewalk(ast, initial, fn
        {{:., _, [{:__aliases__, _, [:Error]}, :new]}, _, [code | _]} = node, codes
        when is_atom(code) ->
          {node, MapSet.put(codes, Atom.to_string(code))}

        {name, _, [code | _]} = node, codes
        when name in [:client_failure, :codec_error] and is_atom(code) ->
          {node, MapSet.put(codes, Atom.to_string(code))}

        {:translate, _, [_error, _limit, size_code, codec_code]} = node, codes
        when is_atom(size_code) and is_atom(codec_code) ->
          {node, put_codes(codes, [size_code, codec_code])}

        {:ensure_size, _, [_payload, _limit, code]} = node, codes when is_atom(code) ->
          {node, MapSet.put(codes, Atom.to_string(code))}

        {:validate_common, _, [_value, code, _label]} = node, codes when is_atom(code) ->
          {node, MapSet.put(codes, Atom.to_string(code))}

        node, codes ->
          {node, codes}
      end)

    codes
  end

  defp put_codes(codes, values) do
    Enum.reduce(values, codes, &MapSet.put(&2, Atom.to_string(&1)))
  end

  defp verify_gate! do
    {configuration, _} = Code.eval_file(".check.exs")
    tools = Keyword.fetch!(configuration, :tools)

    exact!(
      Keyword.get(tools, :stable_api),
      [command: "mix run --no-start bin/check_stable_api.exs"],
      "stable API gate"
    )

    exact!(Keyword.get(tools, :ex_unit), false, "duplicate ExUnit tool")
  end

  defp exact!(actual, expected, label) do
    unless actual == expected do
      violation("#{label} is #{inspect(actual)}; expected #{inspect(expected)}")
    end
  end

  defp require!(source, value, message) do
    unless String.contains?(source, value), do: violation(message)
  end

  defp section!(source, opening, closing) do
    with [_, rest] <- String.split(source, opening, parts: 2),
         [section, _] <- String.split(rest, closing, parts: 2) do
      section
    else
      _ -> violation("stable API error manifest markers are missing")
    end
  end

  defp violation(message), do: throw({:violation, message})

  defp report(:ok) do
    IO.puts("stable API vectors: WBM-S01..WBM-S08")

    IO.puts(
      "0.1 callable surface, callbacks, values, mappings, errors, and migration policy: frozen"
    )

    IO.puts(
      "publication, current-draft parity, registry membership, and broker interoperability: not claimed"
    )

    :ok
  end

  defp report({:violation, message}) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Binding.MQTT.Check.StableAPI.main()
