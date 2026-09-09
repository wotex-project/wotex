# Compiled only when the optional package behind this seam is present;
# the base package stays usable without it.
if Code.ensure_loaded?(Wotex.Runtime.Transport) do
  defmodule Wotex.Lab.Adapters.Runtime.NoSec do
    @moduledoc """
    Credential port for Things whose selected security is `nosec` only.

    It resolves to `nil` credential material when every selected security
    definition uses the `nosec` scheme and refuses anything else, so a Form that
    requires a real scheme can never run without an explicit credential provider.

    Runtime passes the already selected security definitions to `resolve/4`.
    This adapter checks each definition and returns a typed Lab error for a
    non-`nosec` scheme or malformed selection. It does not infer security from
    a URI, modify a Form, or downgrade an authenticated requirement.

    Use this implementation for explicitly unsecured local simulations and
    reference endpoints. Deployments that select bearer, basic, certificate,
    or other credential schemes must provide a separate
    `Wotex.Runtime.Credentials` implementation with appropriate secret
    resolution and audience controls.
    """

    @behaviour Wotex.Runtime.Credentials

    alias Wotex.Lab.Error

    @impl Wotex.Runtime.Credentials
    def resolve(%{definitions: definitions}, _, _, _) when is_map(definitions) do
      if Enum.all?(definitions, fn {_, definition} -> nosec?(definition) end) do
        {:ok, nil}
      else
        {:error,
         Error.new(:security_scheme_not_nosec, :credentials, "selected security is not nosec")}
      end
    end

    def resolve(_, _, _, _) do
      {:error,
       Error.new(:invalid_security_selection, :credentials, "security selection is invalid")}
    end

    defp nosec?(%{"scheme" => "nosec"}), do: true
    defp nosec?(_), do: false
  end
end
