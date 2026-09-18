defmodule Wotex.Lab.Graph.Descriptors do
  @moduledoc """
  The Lab-owned descriptors the knowledge graph joins with the catalogues:
  scenarios with their required steps, the reference adapters and the seam
  each one implements, the Lab-owned seams that have no upstream owner, and
  the ownership questions a retrieval evaluation must answer.

  Everything here is inert data with string identifiers. Scenario `requires`
  and step `requires` form the dependency graph the generator checks for
  cycles; adapter `ownership` must equal the ownership recorded for the seam,
  or the generator rejects the change as undeclared.
  """

  @lab_repository "https://github.com/wotex-project/wotex-lab"

  @type scenario :: %{
          id: String.t(),
          title: String.t(),
          spec: String.t(),
          completion: String.t(),
          status: String.t(),
          capabilities: [String.t()],
          requires: [String.t()],
          adapters: [String.t()],
          steps: [%{id: String.t(), requires: [String.t()]}]
        }

  @type adapter :: %{
          id: String.t(),
          module: String.t(),
          seam: String.t(),
          ownership: String.t(),
          spec: String.t(),
          path: String.t(),
          status: String.t()
        }

  @type seam :: %{
          id: String.t(),
          package: String.t(),
          module: String.t() | nil,
          callbacks: [String.t()],
          ownership: String.t(),
          path: String.t() | nil,
          lab_spec: String.t(),
          status: String.t()
        }

  @type question :: %{
          id: atom(),
          question: String.t(),
          package: String.t(),
          spec: String.t(),
          seam: String.t(),
          adapter: String.t() | nil,
          fixture: String.t(),
          statement: String.t()
        }

  @doc "The canonical Lab repository URL used for revision-specific source links."
  @spec repository() :: String.t()
  def repository, do: @lab_repository

  @doc "Lab scenarios, one per WLB.07 cookbook row, with their required steps."
  @spec scenarios() :: [scenario()]
  def scenarios do
    [
      scenario("parse-td", "Parse, validate and encode TD and TM", "WLB.03", "WLB-C03",
        status: "implemented",
        capabilities: ["core.parse", "core.validate", "core.encode"],
        adapters: [],
        steps: ["parse", "validate", "encode", "reparse"]
      ),
      scenario("thermal-nx", "Observations to an inert proposal", "WLB.03", "WLB-C03",
        status: "implemented",
        capabilities: ["nx.encode", "nx.evaluate", "nx.decode"],
        adapters: ["unit_converter"],
        requires: ["parse-td"],
        steps: ["parse", "encode", "infer", "decode"]
      ),
      scenario("window-anomaly", "Windows, masks and anomaly thresholds", "WLB.03", "WLB-C03",
        status: "implemented",
        capabilities: ["nx.window", "nx.encode", "nx.evaluate", "nx.decode"],
        adapters: [],
        steps: ["simulate", "resample", "encode", "score", "decode"]
      ),
      scenario("serving-batches", "Inline and supervised Nx.Serving", "WLB.03", "WLB-C03",
        status: "partial",
        capabilities: ["nx.encode", "nx.serving"],
        adapters: [],
        requires: ["thermal-nx"],
        steps: ["encode", "serve-inline", "serve-supervised", "correlate"]
      ),
      scenario("axon-room-model", "Reproducible training split and evaluation", "WLB.03", "WLB-C03",
        status: "planned",
        capabilities: ["nx.split", "nx.evaluate"],
        adapters: [],
        steps: ["simulate", "split", "window", "fit", "evaluate"]
      ),
      scenario("consume-http", "Property reads over HTTP", "WLB.04", "WLB-C04",
        status: "implemented",
        capabilities: ["runtime.read", "http.request"],
        adapters: ["req_client", "no_sec"],
        steps: ["serve", "consume", "read", "refuse"]
      ),
      scenario("write-and-act", "Writes and Actions over HTTP", "WLB.04", "WLB-C04",
        status: "implemented",
        capabilities: ["runtime.write", "runtime.invoke", "http.request"],
        adapters: ["req_client", "static_ref"],
        requires: ["consume-http"],
        steps: ["serve", "consume", "write", "invoke", "refuse"]
      ),
      scenario("observe-sse", "SSE observation, reconnect and stop", "WLB.04", "WLB-C04",
        status: "implemented",
        capabilities: ["runtime.observe", "http.subscribe"],
        adapters: ["req_client", "static_ref"],
        requires: ["consume-http"],
        steps: ["serve", "subscribe", "deliver", "reconnect", "stop"]
      ),
      scenario(
        "consume-mqtt",
        "Retained reads, publications and subscriptions",
        "WLB.04",
        "WLB-C04",
        status: "implemented",
        capabilities: ["runtime.read", "runtime.write", "runtime.observe", "mqtt.client"],
        adapters: ["emqtt_client", "no_sec"],
        steps: ["peer", "read-retained", "publish", "subscribe", "refuse"]
      ),
      scenario("expose-thing", "Exposed Thing with explicit ingress", "WLB.04", "WLB-C04",
        status: "implemented",
        capabilities: ["runtime.expose", "runtime.loopback"],
        adapters: ["loopback", "static_ref"],
        steps: ["host", "consume", "admit", "refuse"]
      ),
      scenario("directory", "Both Directory stores", "WLB.05", "WLB-C05",
        status: "implemented",
        capabilities: ["directory.register", "directory.list", "directory.expire"],
        adapters: ["ets_repository", "sqlite_repository", "authorization", "clock", "identifier"],
        steps: ["store", "register", "race", "page", "expire", "reopen"]
      ),
      scenario("continuum", "Continuum exchange, replay and inert intents", "WLB.05", "WLB-C05",
        status: "implemented",
        capabilities: ["continuum.exchange", "continuum.replay"],
        adapters: ["channel", "loopback", "static_ref"],
        requires: ["expose-thing"],
        steps: ["channel", "manifest", "intent", "replay", "bound"]
      ),
      scenario("conformance", "Independent conformance target", "WLB.06", "WLB-C07",
        status: "implemented",
        capabilities: ["conformance.target"],
        adapters: ["conformance_target"],
        requires: ["parse-td"],
        steps: ["archive", "target", "run", "refuse"]
      ),
      scenario("smart-room", "Discovery to one explicit effect", "WLB.05", "WLB-C06",
        status: "implemented",
        capabilities: ["directory.list", "runtime.read", "nx.evaluate", "policy.dispatch"],
        adapters: [
          "ets_repository",
          "req_client",
          "emqtt_client",
          "loopback",
          "static_ref",
          "channel",
          "policy"
        ],
        requires: [
          "thermal-nx",
          "consume-http",
          "consume-mqtt",
          "expose-thing",
          "directory",
          "continuum"
        ],
        steps: ["discover", "observe", "exchange", "infer", "decide", "dispatch", "effect"]
      ),
      scenario("formal-control", "Conflicting rules and bounded search", "WLB.09", "WLB-C09",
        status: "partial",
        capabilities: ["policy.decide", "formal.search"],
        adapters: ["policy"],
        requires: ["smart-room"],
        steps: ["decide", "conflict", "search", "replay"]
      ),
      scenario("nerves-and-mcp", "Bootable target and assistant access", "WLB.08", "WLB-C10",
        status: "partial",
        capabilities: ["design.tokens", "evidence.record", "scenario.descriptor"],
        adapters: [],
        steps: ["tokens", "record", "descriptor", "boot", "assistant"]
      )
    ]
  end

  @doc "Lab reference adapters and the seam each one implements."
  @spec adapters() :: [adapter()]
  def adapters do
    [
      adapter("loopback", "Wotex.Lab.Adapters.Runtime.Loopback", "runtime.transport", "WLB.04",
        path: "lib/wotex/lab/adapters/runtime/loopback.ex"
      ),
      adapter("no_sec", "Wotex.Lab.Adapters.Runtime.NoSec", "runtime.credentials", "WLB.04",
        path: "lib/wotex/lab/adapters/runtime/no_sec.ex"
      ),
      adapter("static_ref", "Wotex.Lab.Adapters.Runtime.StaticRef", "runtime.credentials", "WLB.04",
        path: "lib/wotex/lab/adapters/runtime/static_ref.ex"
      ),
      adapter("req_client", "Wotex.Lab.Adapters.HTTP.ReqClient", "http.client", "WLB.04",
        path: "lib/wotex/lab/adapters/http/req_client.ex"
      ),
      adapter("emqtt_client", "Wotex.Lab.Adapters.MQTT.EmqttClient", "mqtt.client", "WLB.04",
        path: "lib/wotex/lab/adapters/mqtt/emqtt_client.ex"
      ),
      adapter(
        "ets_repository",
        "Wotex.Lab.Adapters.Directory.EtsRepository",
        "directory.repository",
        "WLB.05",
        path: "lib/wotex/lab/adapters/directory/ets_repository.ex"
      ),
      adapter(
        "sqlite_repository",
        "Wotex.Lab.Adapters.Directory.SqliteRepository",
        "directory.repository",
        "WLB.05",
        path: "lib/wotex/lab/adapters/directory/sqlite_repository.ex"
      ),
      adapter(
        "authorization",
        "Wotex.Lab.Adapters.Directory.Authorization",
        "directory.authorization",
        "WLB.05",
        path: "lib/wotex/lab/adapters/directory/authorization.ex"
      ),
      adapter("clock", "Wotex.Lab.Adapters.Directory.Clock", "directory.clock", "WLB.05",
        path: "lib/wotex/lab/adapters/directory/clock.ex"
      ),
      adapter(
        "identifier",
        "Wotex.Lab.Adapters.Directory.Identifier",
        "directory.identifier",
        "WLB.05",
        path: "lib/wotex/lab/adapters/directory/identifier.ex"
      ),
      adapter(
        "unit_converter",
        "Wotex.Lab.Adapters.Nx.UnitConverter",
        "nx.unit_converter",
        "WLB.03",
        path: "lib/wotex/lab/adapters/nx/unit_converter.ex"
      ),
      adapter("policy", "Wotex.Lab.SmartRoom.Policy", "lab.policy", "WLB.05",
        ownership: "lab-owned",
        path: "lib/wotex/lab/smart_room/policy.ex"
      ),
      adapter("channel", "Wotex.Lab.Continuum.Channel", "lab.continuum_channel", "WLB.05",
        ownership: "lab-owned",
        path: "lib/wotex/lab/continuum/channel.ex"
      ),
      adapter(
        "conformance_target",
        "Wotex.Lab.Conformance.Target",
        "lab.conformance_target",
        "WLB.06",
        ownership: "lab-owned",
        path: "lib/wotex/lab/conformance/target.ex"
      )
    ]
  end

  @doc "Seams the Lab owns itself; upstream seams come from the source index."
  @spec seams() :: [seam()]
  def seams do
    [
      %{
        id: "lab.instance",
        package: "wotex_lab",
        module: "Wotex.Lab.Supervisor",
        callbacks: ["child_spec/1", "start_link/1", "start_child/3"],
        ownership: "lab-owned",
        path: "lib/wotex/lab/supervisor.ex",
        lab_spec: "WLB.01",
        status: "implemented"
      },
      %{
        id: "lab.policy",
        package: "wotex_lab",
        module: "Wotex.Lab.SmartRoom.Policy",
        callbacks: ["decide/3", "dispatch/4", "revoke/2", "records/1"],
        ownership: "lab-owned",
        path: "lib/wotex/lab/smart_room/policy.ex",
        lab_spec: "WLB.05",
        status: "implemented"
      },
      %{
        id: "lab.continuum_channel",
        package: "wotex_lab",
        module: "Wotex.Lab.Continuum.Channel",
        callbacks: ["send_value/4", "ack/2", "disconnect/1", "reconnect/1"],
        ownership: "lab-owned",
        path: "lib/wotex/lab/continuum/channel.ex",
        lab_spec: "WLB.05",
        status: "implemented"
      },
      %{
        id: "lab.conformance_target",
        package: "wotex_lab",
        module: "Wotex.Lab.Conformance.Target",
        callbacks: ["respond/1", "run/2", "main/1"],
        ownership: "lab-owned",
        path: "lib/wotex/lab/conformance/target.ex",
        lab_spec: "WLB.06",
        status: "implemented"
      },
      %{
        id: "lab.formal_verification",
        package: "wotex_lab",
        module: "Wotex.Lab.Formal.Profile",
        callbacks: ["new/1", "child_spec/1", "verify/5", "stop/4"],
        ownership: "lab-owned",
        path: "lib/wotex/lab/formal/profile.ex",
        lab_spec: "WLB.09",
        status: "implemented"
      }
    ]
  end

  @doc "The ownership questions of WLB.07 and the graph nodes that answer them."
  @spec questions() :: [question()]
  def questions do
    [
      %{
        id: :redirects,
        question: "Who owns HTTP redirects?",
        package: "wotex_lab",
        spec: "WLB.04",
        seam: "http.client",
        adapter: "req_client",
        fixture: "http-room",
        statement:
          "The consumer-implemented HTTP client refuses to follow redirects; a 3xx " <>
            "response is reported as a permanent http_status failure by the binding."
      },
      %{
        id: :reconnect,
        question: "Who owns reconnect?",
        package: "wotex_lab",
        spec: "WLB.04",
        seam: "runtime.credentials",
        adapter: "static_ref",
        fixture: "http-room",
        statement:
          "Reconnect is a host decision: a permanent subscription child spec is restarted " <>
            "by the instance and re-enters credential resolution; no client reconnects itself."
      },
      %{
        id: :supervision,
        question: "Who owns supervision?",
        package: "wotex_lab",
        spec: "WLB.01",
        seam: "lab.instance",
        adapter: nil,
        fixture: "loopback-room",
        statement:
          "The consumer owns supervision: an explicit Lab instance with anonymous Thing " <>
            "and session supervisors placed by the caller; loading the library starts nothing."
      },
      %{
        id: :remote_contexts,
        question: "Who owns remote execution contexts?",
        package: "wotex_continuum",
        spec: "wotex_continuum:WCT.01",
        seam: "lab.continuum_channel",
        adapter: "channel",
        fixture: "continuum-manifest",
        statement:
          "wotex_continuum defines execution scopes, manifests and compatibility; the Lab " <>
            "host admits a remote context only through a compatible manifest."
      },
      %{
        id: :directory_storage,
        question: "Who owns Directory storage?",
        package: "wotex_lab",
        spec: "WLB.05",
        seam: "directory.repository",
        adapter: "sqlite_repository",
        fixture: "directory-room",
        statement:
          "Storage is consumer-implemented behind the Directory repository port; the Lab " <>
            "supplies an ETS store and an independent SQLite store under one contract suite."
      },
      %{
        id: :nx_effects,
        question: "Who owns Nx effects?",
        package: "wotex_lab",
        spec: "WLB.03",
        seam: "lab.policy",
        adapter: "policy",
        fixture: "thermal-nx",
        statement:
          "wotex_nx output is inert; only the consumer policy may dispatch a decoded " <>
            "proposal, once, after binding identity, watermark, revision and expiry."
      },
      %{
        id: :continuum_intent,
        question: "Who owns Continuum intent?",
        package: "wotex_lab",
        spec: "WLB.05",
        seam: "lab.continuum_channel",
        adapter: "channel",
        fixture: "continuum-manifest",
        statement:
          "An action_intent is a request to execute; the Lab host dispatches it at most " <>
            "once per idempotency key and refuses it without an admitted manifest."
      },
      %{
        id: :formal_verification,
        question: "Who owns formal verification?",
        package: "wotex_lab",
        spec: "WLB.09",
        seam: "lab.formal_verification",
        adapter: nil,
        fixture: "loopback-room",
        statement:
          "The planned ex_maude profile explores modeled transitions at the consumer " <>
            "policy boundary; no verifier result grants an Action, and no source exists yet."
      }
    ]
  end

  defp scenario(id, title, spec, completion, opts) do
    %{
      id: id,
      title: title,
      spec: spec,
      completion: completion,
      status: Keyword.fetch!(opts, :status),
      capabilities: Keyword.fetch!(opts, :capabilities),
      requires: Keyword.get(opts, :requires, []),
      adapters: Keyword.fetch!(opts, :adapters),
      steps: chain(Keyword.fetch!(opts, :steps))
    }
  end

  # Steps are a required order: each step requires the one before it.
  defp chain(ids) do
    ids
    |> Enum.with_index()
    |> Enum.map(fn {id, index} ->
      %{id: id, requires: if(index == 0, do: [], else: [Enum.at(ids, index - 1)])}
    end)
  end

  defp adapter(id, module, seam, spec, opts) do
    %{
      id: id,
      module: module,
      seam: seam,
      ownership: Keyword.get(opts, :ownership, "consumer-implements"),
      spec: spec,
      path: Keyword.fetch!(opts, :path),
      status: "implemented"
    }
  end
end
