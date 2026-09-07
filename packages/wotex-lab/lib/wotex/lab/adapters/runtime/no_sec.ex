defmodule Wotex.Lab.Adapters.Runtime.NoSec do
  @moduledoc """
  Credential port for Things whose selected security is `nosec` only.

  It resolves to `nil` credential material when every selected security
  definition uses the `nosec` scheme and refuses anything else, so a Form that
  requires a real scheme can never run without an explicit credential provider.
  """

  @behaviour Wotex.Runtime.Credentials

  alias Wotex.Lab.Error

  @impl Wotex.Runtime.Credentials
  def resolve(%{definitions: definitions}, _form, _context, _config) when is_map(definitions) do
    if Enum.all?(definitions, fn {_name, definition} -> nosec?(definition) end) do
      {:ok, nil}
    else
      {:error,
       Error.new(:security_scheme_not_nosec, :credentials, "selected security is not nosec")}
    end
  end

  def resolve(_security, _form, _context, _config) do
    {:error, Error.new(:invalid_security_selection, :credentials, "security selection is invalid")}
  end

  defp nosec?(%{"scheme" => "nosec"}), do: true
  defp nosec?(_definition), do: false
end
