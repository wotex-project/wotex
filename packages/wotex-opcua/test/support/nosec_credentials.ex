defmodule Wotex.OPCUA.TestNosecCredentials do
  @moduledoc false

  @behaviour Wotex.Runtime.Credentials

  @impl Wotex.Runtime.Credentials
  def resolve(%{names: ["none"], definitions: %{"none" => %{"scheme" => "nosec"}}}, _, _, _),
    do: {:ok, nil}

  def resolve(
        %{names: ["nosec_sc"], definitions: %{"nosec_sc" => %{"scheme" => "nosec"}}},
        _,
        _,
        _
      ),
      do: {:ok, nil}

  def resolve(_, _, _, _), do: {:error, :unsupported_security}
end
