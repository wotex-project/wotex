defmodule Wotex.CoAP.Test.RuntimeSecurityCredentials do
  @moduledoc false

  @behaviour Wotex.Runtime.Credentials
  @impl Wotex.Runtime.Credentials
  def resolve(_, _, _, credential), do: {:ok, credential}
end
