defmodule Wotex.Modbus.RuntimeCredentials do
  @moduledoc false

  @behaviour Wotex.Runtime.Credentials
  alias Wotex.Modbus.Error

  @impl Wotex.Runtime.Credentials
  def resolve(
        %{names: ["none"], definitions: %{"none" => %{"scheme" => "nosec"}}},
        _,
        _,
        credential
      ),
      do: {:ok, credential}

  def resolve(_, _, _, _), do: {:error, Error.new(:unsupported_security, :security)}
end
