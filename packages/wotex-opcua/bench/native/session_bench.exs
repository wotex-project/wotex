Code.require_file("support/credentials.exs", __DIR__)
Code.require_file("support/peer.exs", __DIR__)

alias Wotex.OPCUA.Bench.NativePeer
alias Wotex.OPCUA.{Browse, Error, Subscription}

# `mix native.bench --package wotex-opcua --workspace DIR` runs this script
# after `wotex.opcua.native.build` built DIR.
workspace = System.fetch_env!("WOTEX_BENCH_WORKSPACE")
peer = NativePeer.start!(workspace, Path.join(System.fetch_env!("WOTEX_BENCH_SCRATCH"), "peer"))
options = NativePeer.session_options(peer, workspace)
object = "ns=#{peer.namespace};s=paged"
child = "ns=#{peer.namespace};s=child1"
burst = "ns=#{peer.namespace};s=burst"
# BadUserAccessDenied: the peer grants anonymous users no write access.
denied = 0x801F_0000

# Benchee measures each job in its own process; the Session opened here makes
# that process the Session owner, which Browse requires.
open_session = fn _ ->
  {:ok, session} = Wotex.OPCUA.connect(options)
  session
end

close_session = fn session -> :ok = Wotex.OPCUA.disconnect(session) end

Benchee.run(
  %{
    "Read of an Int32 Value" => fn session ->
      {:ok, %{"value" => %{"type" => "Int32", "value" => 1}}} =
        Wotex.OPCUA.send(session, %{type: :read, node_id: child})
    end,
    "Write of a Double, rejected with BadUserAccessDenied" => fn session ->
      {:error, %Error{code: :remote_error, details: %{status: ^denied}}} =
        Wotex.OPCUA.send(session, %{
          type: :write,
          node_id: burst,
          value: %{type: "Double", value: 21.5}
        })
    end,
    "Browse page of one reference and release of its continuation" => fn session ->
      {:ok, %Browse.Page{status: 0, references: [_], continuation: continuation}} =
        Browse.references(session, object, page_size: 1)

      :ok = Browse.release(session, continuation)
    end,
    "Browse of three children in three pages" => fn session ->
      {:ok, %{status: 0, references: [_, _, _]}} = Browse.all(session, object, page_size: 1)
    end,
    "Subscribe and unsubscribe a Value MonitoredItem" => fn session ->
      {:ok, %Subscription{reference: reference} = subscription} =
        Wotex.OPCUA.subscribe(session, %{
          node_id: child,
          publishing_interval_ms: 100,
          sampling_interval_ms: 0,
          queue_size: 1
        })

      :ok = Wotex.OPCUA.unsubscribe(session, subscription)
      NativePeer.flush(reference)
    end
  },
  before_scenario: open_session,
  after_scenario: close_session,
  warmup: 1,
  time: 5,
  memory_time: 0,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: System.fetch_env!("WOTEX_BENCH_OUTPUT"),
     title: "# " <> System.fetch_env!("WOTEX_BENCH_TITLE"),
     description: System.fetch_env!("WOTEX_BENCH_DESCRIPTION")}
  ]
)

:ok = NativePeer.await_idle!(peer)
:ok = NativePeer.stop(peer)
