# Compiled only when the optional package behind this seam is present;
# the base package stays usable without it.
if Code.ensure_loaded?(Wotex.Runtime.Transport) do
  defmodule Wotex.Lab.Adapters.Runtime.StaticRef do
    @moduledoc """
    Credential port that resolves secret references at invocation time.

    Configuration must hold references instead of secrets: `references` maps a
    selected security-definition name to an opaque reference, and `lookup` is a
    consumer-owned one-arity function that turns a reference into the secret at
    resolution time. The resolved map (`security name => secret`) is returned for
    the ephemeral execution context of one port call. `nosec` definitions need no
    reference. Errors never echo references or secrets.

    `Wotex.Runtime` supplies the validated security selection. For each selected
    name that is not `nosec`, this adapter requires a reference and a successful
    lookup. Missing references and invalid configuration return errors before
    transport invocation. The adapter does not validate a complete Thing
    Description or sanitize opaque references; the host supplies those values
    and owns the lookup function and secret store.
    """

    @behaviour Wotex.Runtime.Credentials

    alias Wotex.Lab.Error

    @impl Wotex.Runtime.Credentials
    def resolve(%{names: names, definitions: definitions}, _form, _context, config)
        when is_list(names) and is_map(definitions) do
      with {:ok, references, lookup} <- configuration(config) do
        names
        |> Enum.reject(&nosec?(Map.get(definitions, &1)))
        |> Enum.reduce_while({:ok, %{}}, &resolve_name(&1, &2, references, lookup))
        |> finish()
      end
    end

    def resolve(_security, _form, _context, _config) do
      {:error,
       Error.new(:invalid_security_selection, :credentials, "security selection is invalid")}
    end

    defp resolve_name(name, {:ok, acc}, references, lookup) do
      with {:ok, reference} <- Map.fetch(references, name),
           {:ok, secret} <- lookup.(reference) do
        {:cont, {:ok, Map.put(acc, name, secret)}}
      else
        _missing -> {:halt, {:error, unresolved(name)}}
      end
    end

    defp unresolved(name) do
      Error.new(:unresolved_reference, :credentials, "no secret reference for a selected scheme",
        details: %{security: name}
      )
    end

    defp configuration(%{references: references, lookup: lookup})
         when is_map(references) and is_function(lookup, 1),
         do: {:ok, references, lookup}

    defp configuration(_config) do
      {:error,
       Error.new(:invalid_credential_config, :credentials, "references and lookup are required")}
    end

    defp finish({:ok, resolved}) when map_size(resolved) == 0, do: {:ok, nil}
    defp finish(result), do: result

    defp nosec?(%{"scheme" => "nosec"}), do: true
    defp nosec?(_definition), do: false
  end
end
