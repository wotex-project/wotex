defmodule Wotex.BLE.BlueZ.Pairing do
  @moduledoc false

  alias Wotex.BLE.{Challenge, Error}

  @kinds Map.new(
           ~w(confirm_passkey request_passkey request_pin authorize_pairing authorize_service display_passkey display_pin)a,
           &{Atom.to_string(&1), &1}
         )

  @capabilities %{
    no_input_no_output: "NoInputNoOutput",
    display_yes_no: "DisplayYesNo",
    keyboard_only: "KeyboardOnly"
  }

  @doc false
  @spec options(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def options(%{capability: capability, agent: {module, config}} = request, default)
      when is_atom(module) and is_map_key(@capabilities, capability) do
    timeout = Map.get(request, :timeout, default)

    if Map.keys(request) -- [:capability, :agent, :timeout] == [] and
         is_integer(timeout) and timeout in 1..60_000 and Code.ensure_loaded?(module) and
         function_exported?(module, :decide, 2) do
      {:ok,
       %{
         module: module,
         config: config,
         capability: Map.fetch!(@capabilities, capability),
         timeout: timeout
       }}
    else
      {:error, Error.new(:invalid_options)}
    end
  end

  def options(_, _), do: {:error, Error.new(:invalid_options)}

  @doc false
  @spec decision(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def decision(challenge, decision) do
    with {:ok, challenge} <- Challenge.new(challenge) do
      reply(challenge.kind, decision)
    end
  end

  @doc false
  @spec challenge(term(), map(), integer(), integer()) :: {:ok, Challenge.t()} | {:error, Error.t()}
  def challenge(
        %{"id" => id, "peer" => peer, "kind" => kind, "value" => value, "timeout_ms" => remaining} =
          input,
        peer,
        deadline,
        now
      )
      when map_size(input) == 5 and is_integer(remaining) and remaining in 1..60_000 and
             deadline > now do
    with {:ok, kind} <- Map.fetch(@kinds, kind),
         {:ok, value} <- prompt_value(kind, value) do
      Challenge.new(%{
        id: id,
        peer: %{
          adapter: peer["adapter"],
          address: peer["address"],
          address_type: peer_type(peer["address_type"])
        },
        kind: kind,
        value: value,
        deadline_ms: min(deadline, now + remaining)
      })
    else
      _ -> {:error, Error.new(:invalid_challenge)}
    end
  end

  def challenge(_, _, _, _), do: {:error, Error.new(:invalid_challenge)}

  @doc false
  @spec invoke(map(), Challenge.t()) :: {:ok, map()} | {:error, Error.t()}
  def invoke(%{module: module, config: config}, challenge) do
    decision(challenge, module.decide(challenge, config))
  rescue
    _ -> invalid()
  catch
    _, _ -> invalid()
  end

  defp prompt_value(:display_passkey, %{"passkey" => passkey, "entered" => entered} = value)
       when map_size(value) == 2 do
    {:ok, %{passkey: passkey, entered: entered}}
  end

  defp prompt_value(:display_passkey, _), do: :error
  defp prompt_value(_, value), do: {:ok, value}
  defp peer_type("public"), do: :public
  defp peer_type("random"), do: :random
  defp peer_type(_), do: nil

  defp reply(_, :reject), do: {:ok, %{"action" => "reject"}}

  defp reply(kind, :accept)
       when kind in [
              :confirm_passkey,
              :authorize_pairing,
              :authorize_service,
              :display_passkey,
              :display_pin
            ],
       do: {:ok, %{"action" => "accept"}}

  defp reply(:request_passkey, {:passkey, value}) when is_integer(value) and value in 0..999_999,
    do: {:ok, %{"action" => "passkey", "value" => value}}

  defp reply(:request_pin, {:pin, value}) when is_binary(value) and byte_size(value) in 1..16 do
    if ascii?(value), do: {:ok, %{"action" => "pin", "value" => value}}, else: invalid()
  end

  defp reply(_, _), do: invalid()
  defp invalid, do: {:error, Error.new(:pairing_rejected)}
  defp ascii?(<<>>), do: true
  defp ascii?(<<byte, rest::binary>>) when byte in 32..126, do: ascii?(rest)
  defp ascii?(_), do: false
end
