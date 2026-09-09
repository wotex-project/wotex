defmodule Wotex.BLE.BlueZ.Pairing do
  @moduledoc false

  alias Wotex.BLE.{Challenge, Error}

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
