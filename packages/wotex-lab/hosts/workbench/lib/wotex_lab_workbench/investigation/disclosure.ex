defmodule WotexLabWorkbench.Investigation.Disclosure do
  @moduledoc """
  States where trusted-local investigation data goes before a question is asked.

  The statement follows the explicitly selected provider. With
  `:codex_then_ollama`, requests first go to the Codex service through the
  signed-in ChatGPT-plan account, so data leaves this host. The configured
  Ollama fallback follows. With `:ollama`, data stays on this host only when the
  configured Ollama base URL is plain HTTP on a loopback host; any other
  endpoint is disclosed as leaving the host. Without a selected provider there
  is nothing to disclose and the composer stays disabled.

  Either provider can receive the same bounded content: the question, the fixed
  skill and BeamLens operator instructions with catalogue metadata, the closed
  current and baseline run summaries, read-only callback results, and the
  node name, operating system, uptime and current time that BeamLens 0.3.1 adds.
  Credentials, session and room tokens, dataset rows, Thing Description
  documents and other sessions' data are not part of that content. This module
  reads configuration only; it performs no provider call or preflight.
  """

  alias WotexLabWorkbench.Investigation.Config

  @app :wotex_lab_workbench
  @sent [
    "the question, at most 4 KiB",
    "the fixed skill and BeamLens operator instructions and metric catalogue metadata",
    "closed summaries of the selected run and its nearest older run, at most 8 KiB",
    "read-only callback results such as metric query answers and digests, at most 16 KiB",
    "BeamLens node information: node name, operating system, uptime and current time"
  ]
  @withheld "Credentials, session and room tokens, dataset rows, Thing Description documents " <>
              "and other sessions' data are not sent."

  @type t :: %{
          available: boolean(),
          leaves_host: boolean(),
          destinations: [String.t()],
          sent: [String.t()],
          withheld: String.t() | nil
        }

  @doc "Describes the configured provider selection without contacting a provider."
  @spec current() :: t()
  def current do
    for_selection(
      Application.get_env(@app, :beamlens_provider, :none),
      Application.get_env(@app, :beamlens_ollama_base_url)
    )
  end

  @doc "Describes one provider selection and Ollama base URL."
  @spec for_selection(term(), term()) :: t()
  def for_selection(:codex_then_ollama, ollama_url) do
    {_, fallback} = ollama(ollama_url)

    disclosure(true, [
      "Codex service through the signed-in ChatGPT-plan account, attempted first",
      fallback <> ", used if Codex is unavailable"
    ])
  end

  def for_selection(:ollama, ollama_url) do
    {local?, destination} = ollama(ollama_url)
    disclosure(not local?, [destination])
  end

  def for_selection(_, _),
    do: %{available: false, leaves_host: false, destinations: [], sent: [], withheld: nil}

  defp disclosure(leaves_host, destinations) do
    %{
      available: true,
      leaves_host: leaves_host,
      destinations: destinations,
      sent: @sent,
      withheld: @withheld
    }
  end

  defp ollama(url) do
    case {Config.loopback_url?(url), url} do
      {true, url} ->
        %URI{host: host, port: port} = URI.parse(url)
        {true, "Ollama on this host at #{host}:#{port}"}

      {false, url} when is_binary(url) ->
        {false, "Ollama at #{URI.parse(url).host || "an unparsed endpoint"}, outside this host"}

      {false, _} ->
        {false, "an unconfigured Ollama endpoint"}
    end
  end
end
