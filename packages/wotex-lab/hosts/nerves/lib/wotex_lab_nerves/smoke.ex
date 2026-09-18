defmodule WotexLabNerves.Smoke do
  @moduledoc """
  Explicit, inert smoke for the admitted Raspberry Pi 4 firmware lane.

  The smoke runs the binary-backend thermal example and performs two reads
  across replacement loopback Thing processes. It never invokes an Action,
  opens a listener or discovers a device. The returned evidence marks boot as
  passed only on the compiled `:rpi4` target; a host run stays truthful and
  records that hardware boot was not run.
  """

  alias Wotex.{Lab, ThingDescription}
  alias Wotex.Lab.Adapters.Runtime.{Loopback, NoSec}
  alias Wotex.Lab.Evidence.{Digest, Record}
  alias Wotex.Lab.Examples.Thermal
  alias Wotex.Lab.Reference.Thing
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, Result}

  @fixture "priv/fixtures/thermal/thing-description.json"
  @source_root Path.expand("../..", __DIR__)
  @source_files [
    "config/config.exs",
    "lib/wotex_lab_nerves/application.ex",
    "lib/wotex_lab_nerves/smoke.ex",
    "mix.exs",
    "mix.lock"
  ]
  @source_tree_digest (case Digest.tree(@source_root, @source_files) do
                         {:ok, digest} -> digest
                         {:error, _} -> raise "Nerves source cohort cannot be digested"
                       end)
  @lock_digest (case Digest.file(Path.join(@source_root, "mix.lock")) do
                  {:ok, digest} -> digest
                  {:error, _} -> raise "Nerves lock cannot be digested"
                end)
  @archives Mix.Dep.Lock.read()
            |> Map.new(fn
              {name, {:hex, _, _, checksum, _, _, _, _}} ->
                {name, "sha256:" <> checksum}

              {name, _} ->
                {name, :missing}
            end)

  @doc "Runs the bounded numerical and loopback-reconnect smoke and returns public evidence."
  @spec run() :: {:ok, %{evidence: Record.t(), result: map()}} | {:error, term()}
  def run do
    with {:ok, thermal} <- Thermal.run(),
         {:ok, before_restart} <- read_temperature(20.0),
         {:ok, after_restart} <- read_temperature(21.0),
         {:ok, evidence} <- evidence(thermal, before_restart, after_restart) do
      {:ok,
       %{
         evidence: evidence,
         result: %{
           proposal: thermal.proposal.input,
           before_restart: before_restart,
           after_restart: after_restart
         }
       }}
    end
  end

  defp read_temperature(value) do
    with {:ok, td} <- thing_description(),
         {:ok, host} <-
           Lab.start_child(
             WotexLabNerves.Lab,
             :things,
             {Thing, td: td, state: %{"temperature" => value}}
           ) do
      try do
        with {:ok, profile} <-
               BindingProfile.new(
                 id: :loopback,
                 schemes: ["loopback"],
                 operations: [:readproperty],
                 media_types: ["application/json"]
               ),
             {:ok, consumed} <-
               ConsumedThing.new(td,
                 profiles: [profile],
                 transports: %{loopback: {Loopback, %{host: host}}},
                 credentials: {NoSec, []}
               ),
             {:ok, %Result{status: :ok, payload: observed}} <-
               ConsumedThing.read_property(
                 consumed,
                 "temperature",
                 Context.new!(request_id: "nerves-smoke-read", deadline: deadline())
               ) do
          {:ok, observed}
        end
      after
        :ok = Lab.stop_child(WotexLabNerves.Lab, :things, host)
      end
    end
  end

  defp thing_description do
    ThingDescription.from_map(%{
      "@context" => Wotex.td_context_1_1(),
      "id" => "urn:wotex:lab:nerves:thermal",
      "title" => "Nerves thermal smoke",
      "security" => ["nosec_sc"],
      "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
      "properties" => %{
        "temperature" => %{
          "type" => "number",
          "unit" => "Cel",
          "forms" => [
            %{
              "href" => "loopback://thermal/properties/temperature",
              "contentType" => "application/json",
              "op" => "readproperty"
            }
          ]
        }
      }
    })
  end

  defp evidence(thermal, before_restart, after_restart) do
    target = Application.fetch_env!(:wotex_lab_nerves, :target)
    fixture = Application.app_dir(:wotex_lab, @fixture)

    Record.new(%{
      scenario_id: "nerves-rpi4-smoke",
      revision: "source",
      attempt: 1,
      source_tree_digest: @source_tree_digest,
      lock_digest: @lock_digest,
      dependencies: dependencies(),
      fixtures: %{"thermal/thing-description.json" => digest!(fixture)},
      seed: 42,
      toolchain: Digest.toolchain(Nx.BinaryBackend),
      budgets: %{deadline_ms: 5_000, max_children: 8},
      inputs: ["fixture:thermal/thing-description.json", "target:#{target}"],
      assertions: [
        %{id: "WLB-C10:rpi4-boot", status: if(target == :rpi4, do: :pass, else: :not_run)},
        %{id: "WLB-C03:thermal-binary", status: assertion(thermal.proposal.input == 22.0)},
        %{
          id: "WLB-C10:loopback-reconnect",
          status: assertion(before_restart == 20.0 and after_restart == 21.0)
        }
      ],
      outcomes: %{
        target: Atom.to_string(target),
        hardware: if(target == :rpi4, do: "compiled-target", else: "not-run"),
        proposal: thermal.proposal.input,
        read_before_restart: before_restart,
        read_after_restart: after_restart
      },
      durations: %{},
      cleanup: %{status: :ok, details: %{things: 0}}
    })
  end

  defp dependencies do
    for app <- [:wotex, :wotex_nx, :wotex_runtime, :wotex_lab, :nx] do
      name = Atom.to_string(app)

      %{
        name: name,
        version: to_string(Application.spec(app, :vsn)),
        archive: Map.get(@archives, app, :missing)
      }
    end
  end

  defp digest!(path) do
    {:ok, digest} = Digest.file(path)
    digest
  end

  defp assertion(true), do: :pass
  defp assertion(false), do: :fail
  defp deadline, do: System.monotonic_time(:millisecond) + 5_000
end
