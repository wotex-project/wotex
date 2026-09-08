defmodule Wotex.Lab.Cookbook do
  @moduledoc """
  The catalogue of the sixteen executable Livebook cookbooks under
  `priv/cookbooks/`.

  Each entry names the notebook, its path inside the packaged `priv`
  directory, the Lab specifications and completion items it evidences, the
  upstream completion items it supplies consumer evidence for, and two
  separate status values: `:lane` is the source status of the underlying Lab
  lane (`:implemented`, `:partial` or `:planned`) and `:evidence` is the
  notebook's own evidence status, `:executable` when every Elixir cell runs
  against the workspace cohort and `:partial` when some cells are
  documentation only because the lane is not built.

  ## Conventions the notebooks follow

  * The first Elixir cell is `Mix.install/1` and names published artifact
    requirements only; the automated runner skips it.
  * Every notebook has the sections in `required_sections/0`.
  * The last Elixir cell returns a map from check id to boolean; `:checks`
    lists the ids the runner expects, so the notebook's stated expected
    output is asserted, not merely described.
  * Notebooks bind `lab` (the instance they start) and, when they write
    files, `tmp_dir`; the runner stops and removes both after a run.

  Reading a notebook happens on request through `read/1`; nothing here reads
  the filesystem or the network when the module loads.
  """

  alias Wotex.Lab.Error

  @type evidence :: :executable | :partial
  @type lane :: :implemented | :partial | :planned

  @type entry :: %{
          id: String.t(),
          title: String.t(),
          path: String.t(),
          specs: [String.t()],
          completion_ids: [String.t()],
          upstream: [String.t()],
          lane: lane(),
          evidence: evidence(),
          checks: [String.t()],
          timeout_ms: pos_integer()
        }

  # WLB.07 requires these sections; the notebooks place "Expected output" after
  # the breakage and telemetry cells so that its checks cell is the last cell.
  @required_sections [
    "Goal",
    "Prerequisites",
    "Package and consumer ownership",
    "Run",
    "Deliberate breakage",
    "Safe telemetry",
    "Expected output",
    "Public seam",
    "Spec and completion IDs",
    "Replacement adapter"
  ]

  @notebooks [
    %{
      id: "parse-td",
      title: "Parse, validate and encode Thing Descriptions and Thing Models",
      specs: ["WLB.03"],
      completion_ids: ["WLB-C03", "WLB-C08"],
      upstream: ["WTX-C01", "WTX-C02", "WTX-C03", "WTX-C04"],
      lane: :implemented,
      evidence: :executable,
      checks: [
        "td-id",
        "validate-ok",
        "canonical-roundtrip",
        "tm-roundtrip",
        "invalid-json-error",
        "schema-violation-path",
        "non-object-refused"
      ],
      timeout_ms: 30_000
    },
    %{
      id: "thermal-nx",
      title: "Observations to an inert proposal with an explicit unit callback",
      specs: ["WLB.03"],
      completion_ids: ["WLB-C03", "WLB-C08"],
      upstream: ["WNX-C03", "WNX-C04"],
      lane: :implemented,
      evidence: :executable,
      checks: [
        "feature-order",
        "observed-masks",
        "proposal-input",
        "convenience-agrees",
        "unit-refused",
        "identity-refused",
        "output-range-refused"
      ],
      timeout_ms: 30_000
    },
    %{
      id: "window-anomaly",
      title: "Windows, quality, masks and anomaly thresholds over a synthetic stream",
      specs: ["WLB.03"],
      completion_ids: ["WLB-C03", "WLB-C08"],
      upstream: ["WNX-C01", "WNX-C02", "WNX-C04"],
      lane: :implemented,
      evidence: :executable,
      checks: [
        "heater-anomalous",
        "quiet-not-anomalous",
        "deterministic",
        "glitch-masked",
        "stale-window-refused",
        "kelvin-refused",
        "dtype-refused"
      ],
      timeout_ms: 30_000
    },
    %{
      id: "serving-batches",
      title: "Inline and supervised Nx.Serving over an encoded batch",
      specs: ["WLB.03"],
      completion_ids: ["WLB-C03", "WLB-C08"],
      upstream: ["WNX-C04", "WNX-C05"],
      lane: :partial,
      evidence: :executable,
      checks: [
        "inline-supervised-agree",
        "concurrent-correlation",
        "batch-keys",
        "serving-stopped"
      ],
      timeout_ms: 30_000
    },
    %{
      id: "axon-room-model",
      title: "Reproducible synthetic training split and held-out evaluation",
      specs: ["WLB.03"],
      completion_ids: ["WLB-C03", "WLB-C08"],
      upstream: [],
      lane: :planned,
      evidence: :partial,
      checks: [
        "split-before-window",
        "no-window-leak",
        "train-statistics-only",
        "model-vs-persistence-scored",
        "manifest-digest"
      ],
      timeout_ms: 30_000
    },
    %{
      id: "consume-http",
      title: "Property reads through Req and the runtime over a real socket",
      specs: ["WLB.04"],
      completion_ids: ["WLB-C04", "WLB-C08"],
      upstream: ["RT-C04", "WBH-C04"],
      lane: :implemented,
      evidence: :executable,
      checks: [
        "read-through-runtime",
        "read-through-client",
        "oversized-refused",
        "deadline-refused",
        "redirect-refused",
        "media-type-refused"
      ],
      timeout_ms: 30_000
    },
    %{
      id: "write-and-act",
      title: "Writes and Actions with status, content type and deadline rejection",
      specs: ["WLB.04"],
      completion_ids: ["WLB-C04", "WLB-C08"],
      upstream: ["RT-C02", "RT-C03", "WBH-C01", "WBH-C03"],
      lane: :implemented,
      evidence: :executable,
      checks: [
        "write-through-runtime",
        "action-accepted",
        "unauthorized-permanent",
        "no-credential-leak",
        "deadline-timeout",
        "retry-decision-stop",
        "media-type-refused"
      ],
      timeout_ms: 30_000
    },
    %{
      id: "observe-sse",
      title: "Real SSE frames, receiver death, reconnect and duplicate stop",
      specs: ["WLB.04"],
      completion_ids: ["WLB-C04", "WLB-C08"],
      upstream: ["RT-C02", "RT-C04", "WBH-C02", "WBH-C03", "WBH-C04"],
      lane: :implemented,
      evidence: :executable,
      checks: [
        "frame-decoded",
        "keepalive-ignored",
        "invalid-frame-reported",
        "receiver-death-stops",
        "reconnect-fresh-credential",
        "duplicate-stop-safe",
        "oversized-event-ends-session"
      ],
      timeout_ms: 30_000
    },
    %{
      id: "consume-mqtt",
      title: "Retained reads, publications, subscriptions, loss and overload over MQTT",
      specs: ["WLB.04"],
      completion_ids: ["WLB-C04", "WLB-C08"],
      upstream: ["WBM-C01", "WBM-C02", "WBM-C03", "WBM-C04"],
      lane: :implemented,
      evidence: :executable,
      checks: [
        "retained-read",
        "write-published",
        "action-published",
        "delivery-decoded",
        "unreachable-refused",
        "no-retained-message",
        "connect-reported",
        "oversized-dropped",
        "transport-down"
      ],
      timeout_ms: 60_000
    },
    %{
      id: "expose-thing",
      title: "An exposed Thing with explicit ingress policy and an exact handler boundary",
      specs: ["WLB.04"],
      completion_ids: ["WLB-C04", "WLB-C08"],
      upstream: ["RT-C03"],
      lane: :implemented,
      evidence: :executable,
      checks: [
        "handler-boundary-counts",
        "operation-not-declared",
        "out-of-range-refused",
        "unauthorized-refused",
        "thing-level-unsupported",
        "explicit-effect",
        "exposed-thing-direct"
      ],
      timeout_ms: 30_000
    },
    %{
      id: "directory",
      title: "Both Directory stores: conflict, paging, expiry and request context",
      specs: ["WLB.05"],
      completion_ids: ["WLB-C05", "WLB-C08"],
      upstream: ["WTD-C01", "WTD-C02", "WTD-C03", "WTD-C04"],
      lane: :implemented,
      evidence: :executable,
      checks: [
        "both-stores-same-contract",
        "conditional-conflict",
        "keyset-paging",
        "cursor-invalidated",
        "expiry",
        "forbidden-context",
        "sqlite-reopen"
      ],
      timeout_ms: 60_000
    },
    %{
      id: "continuum",
      title: "Continuum compatibility, values, disconnect and replay, inert intents",
      specs: ["WLB.05"],
      completion_ids: ["WLB-C05", "WLB-C08"],
      upstream: ["WCT-C01", "WCT-C02", "WCT-C03", "WCT-C04"],
      lane: :implemented,
      evidence: :executable,
      checks: [
        "manifest-compatible",
        "manifest-incompatible",
        "intent-without-manifest-inert",
        "duplicate-intent-once",
        "reordered-proposal-stale",
        "dropped-delivery",
        "replay-after-reconnect",
        "capacity-bounded"
      ],
      timeout_ms: 30_000
    },
    %{
      id: "conformance",
      title: "An independent conformance target with distinct failure outcomes",
      specs: ["WLB.06"],
      completion_ids: ["WLB-C07", "WLB-C08"],
      upstream: ["WCF-C01", "WCF-C02", "WCF-C03", "WCF-C04"],
      lane: :implemented,
      evidence: :executable,
      checks: [
        "td-corpus-pass",
        "tm-corpus-pass",
        "changed-archive-refused",
        "unsupported-operation",
        "non-object-refused",
        "no-expectations-in-target"
      ],
      timeout_ms: 180_000
    },
    %{
      id: "smart-room",
      title: "Discovery to numeric proposal to one explicit simulated effect",
      specs: ["WLB.03", "WLB.04", "WLB.05", "WLB.06"],
      completion_ids: ["WLB-C06", "WLB-C08"],
      upstream: [],
      lane: :implemented,
      evidence: :executable,
      checks: [
        "things-discovered",
        "proposal-in-limits",
        "decision-granted",
        "dispatched-once",
        "effect-observed",
        "result-crossed-channel",
        "second-dispatch-refused",
        "meter-lowers-target"
      ],
      timeout_ms: 60_000
    },
    %{
      id: "formal-control",
      title: "Conflicting control rules, bounded search and counterexample replay",
      specs: ["WLB.09"],
      completion_ids: ["WLB-C09", "WLB-C08"],
      upstream: [],
      lane: :implemented,
      evidence: :partial,
      checks: [
        "conflicting-rule-refused",
        "dispatch-once",
        "revoked-inert",
        "stale-observation-inert",
        "action-counter-unchanged"
      ],
      timeout_ms: 30_000
    },
    %{
      id: "nerves-and-mcp",
      title: "A bootable target and explicit assistant access",
      specs: ["WLB.07", "WLB.08"],
      completion_ids: ["WLB-C08", "WLB-C10"],
      upstream: [],
      lane: :partial,
      evidence: :partial,
      checks: [
        "tokens-both-themes",
        "stylesheet-scoped",
        "evidence-record-digest",
        "archive-missing-stated",
        "scenario-descriptor-data"
      ],
      timeout_ms: 30_000
    }
  ]

  @doc "The section headings every notebook must carry, in the documented order."
  @spec required_sections() :: [String.t()]
  def required_sections, do: @required_sections

  @doc "Lists every notebook entry in the order of the WLB.07 cookbook table."
  @spec list() :: [entry()]
  def list, do: Enum.map(@notebooks, &Map.put(&1, :path, "priv/cookbooks/" <> &1.id <> ".livemd"))

  @doc "Fetches one entry by id."
  @spec fetch(String.t()) :: {:ok, entry()} | {:error, Error.t()}
  def fetch(id) when is_binary(id) do
    case Enum.find(list(), &(&1.id == id)) do
      nil -> {:error, Error.new(:unknown_cookbook, :catalogue, "no cookbook has this id")}
      entry -> {:ok, entry}
    end
  end

  def fetch(_id),
    do: {:error, Error.new(:unknown_cookbook, :catalogue, "cookbook id must be a string")}

  @doc "Reads a notebook's Livebook source from the packaged `priv` directory."
  @spec read(String.t()) :: {:ok, binary()} | {:error, Error.t()}
  def read(id) do
    with {:ok, entry} <- fetch(id) do
      case File.read(Application.app_dir(:wotex_lab, entry.path)) do
        {:ok, source} ->
          {:ok, source}

        {:error, reason} ->
          {:error,
           Error.new(:cookbook_unreadable, :catalogue, "notebook source cannot be read",
             details: %{reason: reason}
           )}
      end
    end
  end

  @doc "Extracts the Elixir code cells (fenced `elixir` blocks) from Livebook source, in order."
  @spec cells(binary()) :: [binary()]
  def cells(source) when is_binary(source) do
    source
    |> String.split(["\r\n", "\n"])
    |> Enum.reduce({[], nil}, &collect_cell/2)
    |> elem(0)
    |> Enum.reverse()
  end

  @doc "Lists the second-level headings present in Livebook source, in order."
  @spec headings(binary()) :: [String.t()]
  def headings(source) when is_binary(source) do
    ~r/^## (.+?)\s*$/m
    |> Regex.scan(source)
    |> Enum.map(&Enum.at(&1, 1))
  end

  @doc "Required sections absent from Livebook source."
  @spec missing_sections(binary()) :: [String.t()]
  def missing_sections(source) when is_binary(source) do
    present = headings(source)
    Enum.reject(@required_sections, &(&1 in present))
  end

  defp collect_cell(line, {cells, nil}) do
    if String.trim_trailing(line) == "```elixir", do: {cells, []}, else: {cells, nil}
  end

  defp collect_cell(line, {cells, lines}) do
    if String.trim_trailing(line) == "```" do
      {[lines |> Enum.reverse() |> Enum.join("\n") | cells], nil}
    else
      {cells, [line | lines]}
    end
  end
end
