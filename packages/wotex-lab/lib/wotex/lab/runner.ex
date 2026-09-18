defmodule Wotex.Lab.Runner do
  @moduledoc """
  The bounded scenario runner: preflight, admitted attempts, replay.

  `preflight/3` checks an approved `Wotex.Lab.Scenario` descriptor, a
  revision-pinned `Wotex.Lab.Runner.Definition` and an explicit
  `Wotex.Lab.Runner.Host` before any child starts: the descriptor and the
  definition must agree on id and capabilities, every required capability
  must be served by a host module, fixture digests must match the files under
  `priv/fixtures`, and budgets must be admissible. An unavailable capability
  is `unsupported`, never a pass. `start/3` admits one attempt with a unique
  id under the host instance's session supervisor and returns its pid;
  `await/2`, `status/1`, `cancel/1` and `kill/1` observe and end it.
  `replay/3` runs the same definition again with the recorded seed and
  compares the logical step stream with the recording.
  """

  alias Wotex.Lab
  alias Wotex.Lab.{Error, Scenario}
  alias Wotex.Lab.Evidence.Digest
  alias Wotex.Lab.Runner.{Attempt, Definition, Host, Recording}

  @type run :: pid()

  @doc "Preflight without starting anything."
  @spec preflight(Scenario.t(), Definition.t(), Host.t()) :: :ok | {:error, Error.t()}
  def preflight(%Scenario{} = scenario, %Definition{} = definition, %Host{} = host) do
    with {:ok, scenario} <- Scenario.revalidate(scenario),
         {:ok, definition} <- Definition.revalidate(definition),
         {:ok, host} <- Host.revalidate(host),
         descriptor = Scenario.to_map(scenario),
         :ok <- agree(descriptor, definition),
         :ok <- capabilities(definition, host) do
      fixtures(definition)
    end
  end

  def preflight(_, _, _),
    do:
      {:error,
       Error.new(:invalid_run, :preflight, "preflight needs a scenario, a definition and a host")}

  @doc "Admits one attempt after preflight; returns its process."
  @spec start(Scenario.t(), Definition.t(), Host.t()) :: {:ok, run()} | {:error, Error.t()}
  def start(scenario, definition, host) do
    with :ok <- preflight(scenario, definition, host) do
      attempt_id = "attempt-" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

      case Lab.start_child(
             host.instance,
             :sessions,
             {Attempt,
              scenario: scenario, definition: definition, host: host, attempt_id: attempt_id}
           ) do
        {:ok, pid} ->
          {:ok, pid}

        {:error, %Error{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error,
           Error.new(:attempt_not_started, :preflight, "attempt could not start",
             details: %{reason: inspect(reason, limit: 5)}
           )}
      end
    end
  end

  @doc "Waits for the terminal status."
  @spec await(run(), timeout()) :: {:ok, map()} | {:error, :timeout}
  defdelegate await(run, timeout \\ 60_000), to: Attempt

  @doc "The current status."
  @spec status(run()) :: map()
  defdelegate status(run), to: Attempt

  @doc "Cancels; idempotent."
  @spec cancel(run()) :: :ok
  defdelegate cancel(run), to: Attempt

  @doc "Forces the attempt to stop; recorded as forced."
  @spec kill(run()) :: :ok
  defdelegate kill(run), to: Attempt

  @doc "Runs the definition again with the recorded seed and compares the logical stream."
  @spec replay(Recording.t(), Definition.t(), Host.t(), timeout()) ::
          {:ok, %{comparison: term(), status: map()}} | {:error, Error.t() | :timeout}
  def replay(recording, definition, host, timeout \\ 60_000)

  def replay(recording, %Definition{} = definition, %Host{} = host, timeout) do
    with :ok <- Recording.validate(recording),
         {:ok, scenario} <-
           Scenario.new(
             id: recording.scenario_id,
             title: "replay of " <> recording.attempt_id,
             capabilities: definition.capabilities,
             seed: recording.seed,
             max_steps: max(length(definition.steps), 1)
           ),
         {:ok, run} <- start(scenario, definition, %{host | seed: recording.seed}),
         {:ok, status} <- await(run, timeout) do
      {:ok, %{comparison: Recording.compare(recording, status.recording), status: status}}
    end
  end

  def replay(_, _, _, _),
    do: {:error, Error.new(:invalid_recording, :preflight, "replay input is invalid")}

  defp agree(descriptor, definition) do
    cond do
      descriptor["id"] != definition.id ->
        {:error,
         Error.new(:descriptor_mismatch, :preflight, "descriptor and definition ids differ",
           details: %{descriptor: descriptor["id"], definition: definition.id}
         )}

      Enum.sort(descriptor["capabilities"]) != Enum.sort(definition.capabilities) ->
        {:error,
         Error.new(
           :descriptor_mismatch,
           :preflight,
           "descriptor and definition capabilities differ"
         )}

      descriptor["max_steps"] < length(definition.steps) ->
        {:error,
         Error.new(
           :step_budget_exhausted,
           :preflight,
           "definition has more steps than the descriptor allows"
         )}

      true ->
        :ok
    end
  end

  defp capabilities(definition, host) do
    case definition.capabilities -- Host.capabilities(host) do
      [] ->
        :ok

      missing ->
        {:error,
         Error.new(:unsupported, :preflight, "host does not serve every required capability",
           details: %{missing: missing}
         )}
    end
  end

  defp fixtures(definition) do
    root = Application.app_dir(:wotex_lab, "priv/fixtures")

    Enum.reduce_while(definition.fixtures, :ok, fn {name, digest}, :ok ->
      path = Path.join(root, name)

      cond do
        not String.starts_with?(Path.expand(path), root) ->
          {:halt,
           {:error,
            Error.new(:invalid_fixture_digest, :preflight, "fixture name escapes the fixture root",
              details: %{fixture: name}
            )}}

        Digest.file(path) == {:ok, digest} ->
          {:cont, :ok}

        true ->
          {:halt,
           {:error,
            Error.new(
              :invalid_fixture_digest,
              :preflight,
              "fixture does not match its recorded digest",
              details: %{fixture: name}
            )}}
      end
    end)
  end
end
