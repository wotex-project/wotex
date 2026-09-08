defmodule Wotex.Lab.MCP.Seams do
  @moduledoc """
  The ownership seams of the WoTEx family as fixed Lab data.

  Each entry names who owns a behaviour that consumers ask about, which
  package and specification carry it, and which Lab module demonstrates it.
  The table is the answer surface for retrieval questions such as who owns
  redirects, reconnect, supervision, remote contexts, Directory storage, Nx
  effects, Continuum intent and formal verification. It is descriptive data,
  not a claim that any package is complete.
  """

  @seams [
    %{
      "id" => "redirects",
      "question" => "Who follows HTTP redirects?",
      "owner" => "wotex_binding_http",
      "spec" => "WBH.01",
      "answer" =>
        "The HTTP binding never follows redirects; a 3xx is a typed error and the consumer decides. The Lab Req client sets redirect: false.",
      "lab_module" => "Wotex.Lab.Adapters.HTTP.ReqClient"
    },
    %{
      "id" => "reconnect",
      "question" => "Who reconnects a lost subscription?",
      "owner" => "wotex_runtime",
      "spec" => "WRT.02",
      "answer" =>
        "A runtime subscription stops with :shutdown on session loss; the caller's supervisor restart policy decides whether it resubscribes with fresh credentials.",
      "lab_module" => "Wotex.Lab.Adapters.HTTP.SSE.Session"
    },
    %{
      "id" => "supervision",
      "question" => "Who supervises Lab processes?",
      "owner" => "wotex_lab",
      "spec" => "WLB.01",
      "answer" =>
        "An explicit Wotex.Lab instance with bounded Thing and session supervisors; loading the library starts nothing.",
      "lab_module" => "Wotex.Lab.Supervisor"
    },
    %{
      "id" => "remote-contexts",
      "question" => "Who resolves remote JSON-LD contexts?",
      "owner" => "wotex",
      "spec" => "WTX.01",
      "answer" =>
        "Nobody fetches them: the core admits the TD 1.1 context in first position and rejects documents that need remote resolution.",
      "lab_module" => "Wotex.Lab.Conformance.Target"
    },
    %{
      "id" => "directory-storage",
      "question" => "Who stores Directory registrations?",
      "owner" => "wotex_lab",
      "spec" => "WLB.05",
      "answer" =>
        "The Directory package defines the repository port; the Lab supplies two independent stores, ETS and SQLite, behind one contract suite.",
      "lab_module" => "Wotex.Lab.Adapters.Directory.EtsRepository"
    },
    %{
      "id" => "nx-effects",
      "question" => "Can an Nx output cause an effect?",
      "owner" => "wotex_lab",
      "spec" => "WLB.03",
      "answer" =>
        "No. Numerical output is inert; only an explicit consumer policy decision dispatches, once, through the runtime.",
      "lab_module" => "Wotex.Lab.SmartRoom.Policy"
    },
    %{
      "id" => "continuum-intent",
      "question" => "Who executes a Continuum action intent?",
      "owner" => "wotex_lab",
      "spec" => "WLB.05",
      "answer" =>
        "A host that owns the target Thing dispatches an intent at most once per idempotency key; an edge that already dispatched forwards only the result.",
      "lab_module" => "Wotex.Lab.Continuum.Host"
    },
    %{
      "id" => "formal-verification",
      "question" => "Who runs formal verification and what does it prove?",
      "owner" => "wotex_lab",
      "spec" => "WLB.09",
      "answer" =>
        "The optional ex_maude profile explores the finite thermal-control model; a result is model-scoped evidence and never an authorization.",
      "lab_module" => "Wotex.Lab.Formal.Profile"
    }
  ]

  @doc "Every seam."
  @spec all() :: [map()]
  def all, do: @seams

  @doc "One seam by id."
  @spec fetch(String.t()) :: {:ok, map()} | :error
  def fetch(id) when is_binary(id) do
    case Enum.find(@seams, &(&1["id"] == id)) do
      nil -> :error
      seam -> {:ok, seam}
    end
  end
end
