defmodule Wotex.BLE.CoreBluetooth.Options do
  @moduledoc false

  alias Wotex.BLE.BlueZ.Artifacts
  alias Wotex.BLE.CoreBluetooth.Peer
  alias Wotex.BLE.Error

  @artifacts ~w(executable executable_sha256 guardian guardian_sha256)a
  @fields [:peer, :generation, :pairing, :permission, :timeout, :owner] ++ @artifacts

  @spec new(term(), pid()) :: {:ok, map()} | {:error, Error.t()}
  def new(input, caller) when is_list(input) do
    with values <- Enum.take(input, length(@fields) + 1),
         true <- Keyword.keyword?(values),
         keys = Keyword.keys(values),
         true <-
           length(keys) <= length(@fields) and keys -- @fields == [] and
             length(Enum.uniq(keys)) == length(keys),
         %Peer{} = selected <- Keyword.get(values, :peer),
         {:ok, peer} <- Peer.new(selected),
         generation = Keyword.get(values, :generation),
         true <- is_integer(generation) and generation in 1..0xFFFF_FFFF_FFFF_FFFF,
         :system <- Keyword.get(values, :pairing),
         permission = Keyword.get(values, :permission, :require_authorized),
         true <- permission in [:require_authorized, :request],
         timeout = Keyword.get(values, :timeout, 5000),
         true <- is_integer(timeout) and timeout in 1..60_000,
         owner = Keyword.get(values, :owner, caller),
         true <- is_pid(owner) and node(owner) == node(),
         {:ok, artifacts} <- Artifacts.new(Keyword.take(values, @artifacts)) do
      {:ok,
       %{
         peer: peer,
         generation: generation,
         permission: permission,
         timeout: timeout,
         owner: owner,
         artifacts: artifacts
       }}
    else
      _ -> {:error, Error.new(:invalid_options)}
    end
  end

  def new(_, _), do: {:error, Error.new(:invalid_options)}
end
