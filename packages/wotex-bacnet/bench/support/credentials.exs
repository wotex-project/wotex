defmodule Wotex.BACnet.Bench.Credentials do
  @moduledoc false

  # Resolves the `nosec` security scheme of the benchmark Thing Descriptions
  # to no credential, which the BACnet Runtime Transport requires.

  @behaviour Wotex.Runtime.Credentials

  @impl Wotex.Runtime.Credentials
  def resolve(%{definitions: definitions}, _, _, _) do
    if Enum.all?(Map.values(definitions), &(&1 == %{"scheme" => "nosec"})),
      do: {:ok, nil},
      else: {:error, :unsupported_security}
  end
end
