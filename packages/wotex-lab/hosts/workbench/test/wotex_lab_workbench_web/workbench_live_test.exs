defmodule WotexLabWorkbenchWeb.WorkbenchLiveTest do
  @moduledoc false

  use WotexLabWorkbenchWeb.ConnCase, async: false

  alias Plug.Conn.Query
  alias WotexLabWorkbench.Observability.Supervisor, as: ObservabilitySupervisor
  alias WotexLabWorkbench.Sessions
  alias WotexLabWorkbenchWeb.ComponentHarness
  alias WotexLabWorkbenchWeb.Components
  alias WotexLabWorkbenchWeb.Components.Shell
  alias WotexLabWorkbenchWeb.Plugs.ContentSecurityPolicy
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

  @beamlens_registry %{
    primary: "Test",
    clients: [
      %{
        name: "Test",
        provider: "openai-generic",
        options: %{base_url: "http://127.0.0.1:1/v1", model: "test"}
      }
    ]
  }
  @beamlens_capability "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

  test "the endpoint issues a scoped session with restrictive headers and no room side effect", %{
    conn: conn
  } do
    before = Sessions.count()
    conn = get(conn, "/")
    html = html_response(conn, 200)

    assert html =~ "Numerical workbench"
    assert html =~ "mounting this page" or html =~ "Start disposable room"
    assert Sessions.count() == before + 1
    assert is_binary(get_session(conn, SessionToken.key()))

    [policy] = get_resp_header(conn, "content-security-policy")
    assert policy =~ "default-src 'self'"
    assert policy =~ "frame-ancestors 'none'"
    assert policy =~ "object-src 'none'"
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
    refute html =~ "https://cdn"
  end

  test "a browser flow runs an experiment and preserves Action separation", %{conn: conn} do
    conn = get(conn, "/")
    {:ok, view, html} = live(recycle(conn), "/")
    assert html =~ "Start disposable room"
    assert html =~ ~s(phx-disable-with="Running…")

    html = render_click(element(view, "button[phx-click='start_room']"))
    assert html =~ "Recent runs"
    refute html =~ "Start disposable room"

    redirect =
      render_submit(element(view, "#run-thermal"), %{
        "experiment_id" => "thermal",
        "params" => %{"backend" => "binary"}
      })

    {:ok, run_view, html} = follow_redirect(redirect, recycle(conn), "/runs/run-1")
    assert html =~ "Tensor summary"
    assert html =~ "setTarget 22.000 Cel (inert)"
    assert html =~ "Run assertions"
    refute html =~ "Approve simulated Action"

    assert render(run_view) =~ "Ask about this run"
  end

  test "a smart-room run needs the separate exact approval form", %{conn: conn} do
    conn = get(conn, "/")
    {:ok, view, _html} = live(recycle(conn), "/")
    render_click(element(view, "button[phx-click='start_room']"))

    redirect =
      render_submit(element(view, "#run-smart_room"), %{
        "experiment_id" => "smart_room",
        "params" => %{
          "power_budget" => "2000",
          "meter" => "on",
          "principal" => "operator",
          "ttl_ms" => "120000"
        }
      })

    {:ok, run_view, html} = follow_redirect(redirect, recycle(conn), "/runs/run-1")
    assert html =~ "Approve simulated Action"
    assert html =~ "Running the experiment did not dispatch it"
    assert html =~ "Proposal digest"

    html = render_submit(element(run_view, "form[phx-submit='approve']"))
    assert html =~ "dispatched"
    assert html =~ "target read back"

    refute has_element?(run_view, "form[phx-submit='approve']")
  end

  test "analysis is explicit, scope-owned and cannot mutate or replay its run", %{conn: conn} do
    conn = get(conn, "/")
    {:ok, view, _html} = live(recycle(conn), "/")
    render_click(element(view, "button[phx-click='start_room']"))
    assert render_hook(view, "inspect_run", %{}) =~ "unknown_run"

    redirect =
      render_submit(element(view, "#run-window_anomaly"), %{
        "experiment_id" => "window_anomaly",
        "params" => %{"backend" => "binary"}
      })

    {:ok, run_view, _html} = follow_redirect(redirect, recycle(conn), "/runs/run-1")
    refute has_element?(run_view, "#run-insights")
    before = get(recycle(conn), "/evidence/report.json") |> json_response(200) |> Map.fetch!("runs")

    html = render_submit(element(run_view, "#run-analysis"), %{"mark" => "point"})
    assert html =~ "Explorer.PolarsBackend"
    assert html =~ "Source preview digest" and html =~ "Analysis query digest"
    assert html =~ "Nonfinite" and html =~ "Observed"
    assert has_element?(run_view, "#analysis-mark option[value='point'][selected]")
    assert has_element?(run_view, "#analysis-deep-link")
    assert html =~ "Exact chart link"
    assert html =~ "analysis[mark]=point"
    render_change(element(run_view, "#theme-settings"), %{"theme" => "dark"})
    assert has_element?(run_view, "#run-insights")
    assert has_element?(run_view, "#analysis-mark option[value='point'][selected]")

    html = render_hook(run_view, "inspect_run", %{"instance_id" => "other"})
    assert html =~ "invalid_analysis_query"

    html =
      render_submit(element(run_view, "#run-analysis"), %{"from" => "1000000", "mark" => "area"})

    assert html =~ "No points match this range. This is not a measured zero."

    exact =
      "/runs/run-1?" <>
        Query.encode(%{
          "analysis" => %{"from" => "", "mark" => "area", "series" => "", "to" => "1000000"}
        })

    assert {:ok, linked, linked_html} = live(recycle(conn), exact)
    assert linked_html =~ "Analysis query digest"
    assert has_element?(linked, "#analysis-mark option[value='area'][selected]")
    assert has_element?(linked, ~s(a[href$="#run-chart-0"]))

    assert {:ok, refused, refused_html} =
             live(recycle(conn), "/runs/run-1?analysis[mark]=caller")

    assert refused_html =~ "invalid_analysis_query"
    refute has_element?(refused, "#run-insights")

    after_runs =
      get(recycle(conn), "/evidence/report.json") |> json_response(200) |> Map.fetch!("runs")

    assert after_runs == before
    {:ok, reloaded, _html} = live(recycle(conn), "/runs/run-1")
    refute has_element?(reloaded, "#run-insights")
    {:ok, other, _html} = live(build_conn(), "/runs/run-1")
    refute has_element?(other, "#run-analysis")
    refute render_hook(other, "inspect_run", %{}) =~ "Explorer.PolarsBackend"
  end

  test "Things escape untrusted TD text and reports stay in the caller session", %{conn: conn} do
    conn = get(conn, "/things")
    {:ok, view, _html} = live(recycle(conn), "/things")
    render_click(element(view, "button[phx-click='start_room']"))

    source =
      Jason.encode!(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:test:web",
        "title" => "<script>alert('x')</script>",
        "security" => ["nosec_sc"],
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}}
      })

    html =
      render_submit(element(view, "form[phx-submit='register_td']"), %{
        "thing_description" => source
      })

    assert html =~ "&lt;script&gt;alert"
    refute html =~ "<script>alert('x')</script>"

    html = render_submit(element(view, "#read-thermostat-temperature"))
    assert html =~ "Latest reading"
    assert html =~ "21.5"

    report = get(recycle(conn), "/evidence/report.json")
    assert json_response(report, 200)["session"] =~ "session-"

    assert get_resp_header(report, "content-disposition") ==
             [~s(attachment; filename="wotex-lab-evidence.json")]
  end

  test "generated tokens, host CSS and optional investigation state are explicit", %{conn: conn} do
    token_conn = get(conn, "/css/tokens.css")
    css = response(token_conn, 200)
    assert get_resp_header(token_conn, "content-type") |> hd() =~ "text/css"
    assert css =~ ".wotex-lab"
    assert css =~ "--wl-color-bg"

    host_css = File.read!(Application.app_dir(:wotex_lab_workbench, "priv/static/css/host.css"))
    assert host_css =~ "prefers-reduced-motion"
    assert host_css =~ "@media (max-width: 48rem)"
    assert host_css =~ ~r/\.wl-stack > \* \{\s*min-width: 0;/
    refute host_css =~ "gradient"

    {:ok, view, _html} = live(conn, "/evidence")
    render_click(element(view, "button[phx-click='start_room']"))
    html = render(view)
    assert html =~ "No investigation provider is configured"
    assert html =~ "not run"
  end

  test "trusted-local browser investigation is owner-bound and renders structured evidence", %{
    conn: conn
  } do
    start_beamlens_tree(fn ->
      %{digest: digest} =
        WotexLabWorkbench.Investigation.Skill.callbacks()["lab_run_summary"].("current")

      {:ok,
       [
         %{
           context: "Run <script>run-1</script>",
           observation: "Metric nx_duration_seconds increased (run summary #{digest}).",
           hypothesis: "Backend contention might explain the increase.",
           snapshots: [%{id: "snapshot-1"}]
         }
       ]}
    end)

    provider = Application.get_env(:wotex_lab_workbench, :beamlens_provider)
    Application.put_env(:wotex_lab_workbench, :beamlens_provider, :codex_then_ollama)
    on_exit(fn -> Application.put_env(:wotex_lab_workbench, :beamlens_provider, provider) end)

    conn = get(conn, "/")
    {:ok, view, _html} = live(recycle(conn), "/")
    render_click(element(view, "button[phx-click='start_room']"))

    redirect =
      render_submit(element(view, "#run-thermal"), %{
        "experiment_id" => "thermal",
        "params" => %{"backend" => "binary"}
      })

    {:ok, run_view, html} = follow_redirect(redirect, recycle(conn), "/runs/run-1")
    assert html =~ "Trusted-local only"
    assert html =~ "Data leaves this host"
    assert has_element?(run_view, "#investigation-disclosure li", "node name, operating system")
    refute has_element?(run_view, "#investigation textarea[disabled]")

    _html = render_submit(element(run_view, "#investigation"), %{"prompt" => "Explain this run"})
    html = render_until(run_view, "Observed facts")
    assert html =~ "Observed facts"
    assert html =~ "Metric nx_duration_seconds increased (run summary sha256:"
    assert html =~ "Backend contention might explain the increase."
    assert html =~ "BeamLens snapshot snapshot-1"
    assert html =~ "Recorded evidence sha256:"
    assert html =~ "&lt;script&gt;run-1&lt;/script&gt;"
    refute html =~ "<script>run-1</script>"
    refute has_element?(run_view, "form[phx-submit='approve']")

    assert_receive {:fake_investigation_context, %{available: true, summary: %{"id" => "run-1"}},
                    %{available: false}},
                   1_000
  end

  test "browser cancellation terminates the worker and clears its prompt context", %{conn: conn} do
    start_beamlens_tree(:block)
    conn = get(conn, "/")
    {:ok, view, _html} = live(recycle(conn), "/")
    render_click(element(view, "button[phx-click='start_room']"))

    redirect =
      render_submit(element(view, "#run-thermal"), %{
        "experiment_id" => "thermal",
        "params" => %{"backend" => "binary"}
      })

    {:ok, run_view, _html} = follow_redirect(redirect, recycle(conn), "/runs/run-1")
    html = render_submit(element(run_view, "#investigation"), %{"prompt" => "Wait for me"})
    assert html =~ "Cancel investigation"
    assert_receive {:fake_investigation_started, worker, "Wait for me"}, 1_000

    _html = render_click(element(run_view, "button[phx-click='cancel_investigation']"))
    html = render_until(run_view, "context was cleared")
    assert html =~ "cancelled"
    assert html =~ "context was cleared"
    refute Process.alive?(worker)
  end

  test "session revocation terminates an active investigation", %{conn: conn} do
    start_beamlens_tree(:block)
    conn = get(conn, "/")
    token = get_session(conn, SessionToken.key())
    {:ok, view, _html} = live(recycle(conn), "/")
    render_click(element(view, "button[phx-click='start_room']"))

    redirect =
      render_submit(element(view, "#run-thermal"), %{
        "experiment_id" => "thermal",
        "params" => %{"backend" => "binary"}
      })

    {:ok, run_view, _html} = follow_redirect(redirect, recycle(conn), "/runs/run-1")
    _html = render_submit(element(run_view, "#investigation"), %{"prompt" => "Wait for me"})
    assert_receive {:fake_investigation_started, worker, "Wait for me"}, 1_000

    assert :ok = Sessions.revoke(token)
    html = render_until(run_view, "session expired or was revoked")
    assert html =~ "cancelled"
    refute Process.alive?(worker)
  end

  test "the component family renders semantic names and text alternatives" do
    html = render_component(&ComponentHarness.render/1, %{})
    assert html =~ "Run"
    assert html =~ ~s(aria-label="Open menu")
    assert html =~ "Run context"
    assert html =~ ~s(aria-describedby="name-help")
    assert html =~ ~s(role="tablist")
    assert html =~ ~s(role="alert")
    assert html =~ "sha256:abc"
    assert html =~ "unavailable"
    assert html =~ "Observed"
  end

  defp start_beamlens_tree(result) do
    saved_runner = Application.get_env(:wotex_lab_workbench, :beamlens_operator_runner)
    saved_owner = Application.get_env(:wotex_lab_workbench, :fake_investigation_owner)
    saved_result = Application.get_env(:wotex_lab_workbench, :fake_investigation_result)

    Application.put_env(
      :wotex_lab_workbench,
      :beamlens_operator_runner,
      WotexLabWorkbench.FakeInvestigationRunner
    )

    Application.put_env(:wotex_lab_workbench, :fake_investigation_owner, self())
    Application.put_env(:wotex_lab_workbench, :fake_investigation_result, result)

    on_exit(fn ->
      restore_env(:beamlens_operator_runner, saved_runner)
      restore_env(:fake_investigation_owner, saved_owner)
      restore_env(:fake_investigation_result, saved_result)
    end)

    start_supervised!(
      {ObservabilitySupervisor,
       history: [interval_ms: 60_000], beamlens: beamlens_options(@beamlens_registry)}
    )
  end

  defp beamlens_options(registry) do
    registry =
      put_in(
        registry,
        [:clients, Access.at(0), :options, :api_key],
        @beamlens_capability
      )

    %{capability: @beamlens_capability, registry: registry}
  end

  defp restore_env(key, nil), do: Application.delete_env(:wotex_lab_workbench, key)
  defp restore_env(key, value), do: Application.put_env(:wotex_lab_workbench, key, value)

  defp render_until(view, expected, attempts \\ 50)
  defp render_until(view, _expected, 0), do: render(view)

  defp render_until(view, expected, attempts) do
    html = render(view)

    if html =~ expected do
      html
    else
      Process.sleep(5)
      render_until(view, expected, attempts - 1)
    end
  end

  test "unknown and stale browser sessions render denial rather than replacement", %{conn: conn} do
    conn = init_test_session(conn, %{SessionToken.key() => "forged"})
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "Session denied"
    assert html =~ "unknown_session"
    assert html =~ "New session"
  end

  test "window, metric, dataset and investigation controls remain separate and bounded", %{
    conn: conn
  } do
    conn = get(conn, "/")
    browser = recycle(conn)
    {:ok, view, _html} = live(browser, "/")

    html = render_click(element(view, "button[phx-click='toggle_sidebar']"))
    assert html =~ ~s(id="wl-sidebar") and html =~ ~s(hidden)

    html = render_change(element(view, "#theme-settings"), %{"theme" => "dark"})
    assert html =~ ~s(data-theme="dark")

    html = render_hook(view, "run", %{})
    assert html =~ "invalid_parameters"
    assert html =~ "Start disposable room"

    render_click(element(view, "button[phx-click='start_room']"))

    redirect =
      render_submit(element(view, "#run-window_anomaly"), %{
        "experiment_id" => "window_anomaly",
        "params" => %{
          "seed" => "7",
          "count" => "32",
          "window_count" => "8",
          "threshold" => "1.5",
          "fill" => "18.0",
          "backend" => "binary"
        }
      })

    {:ok, _run_view, html} = follow_redirect(redirect, recycle(conn), "/runs/run-1")
    assert html =~ "window_anomaly"
    assert html =~ "simulated temperature (Cel)"
    assert html =~ "Persistence prediction"
    assert html =~ "Data table alternative"

    {:ok, metrics, html} = live(recycle(conn), "/metrics")
    assert html =~ "Session measurements"

    html =
      render_submit(element(metrics, "#metric-query"), %{
        "component" => "scenario",
        "operation" => "inference"
      })

    assert html =~ "Retained samples"
    assert html =~ "Bounded session metric samples"

    html =
      render_submit(element(metrics, "#metric-query"), %{
        "component" => "caller",
        "operation" => "inference"
      })

    assert html =~ "invalid_filter"
    render_click(element(metrics, "button[phx-click='export_dataset']"))

    {:ok, evidence, html} = live(recycle(conn), "/evidence")
    assert html =~ "Bounded session report"

    {property, _description} = Enum.at(WotexLabWorkbench.Formal.properties(), 0)

    html =
      render_submit(element(evidence, "#formal-verify"), %{
        "property" => Atom.to_string(property),
        "variant" => "safe"
      })

    assert html =~ "unsupported"

    html = render_submit(element(evidence, "#investigation"), %{"prompt" => "status?"})
    assert html =~ "No investigation provider is configured"

    report = get(recycle(conn), "/evidence/report.json") |> json_response(200)
    assert [%{"rows" => rows}] = report["datasets"]
    assert rows > 0 and report["runs"] |> hd() |> Map.fetch!("experiment") == "window_anomaly"
  end

  test "cancel, session reset, token overrides and hostile Host text have explicit outcomes", %{
    conn: conn
  } do
    conn = get(conn, "/")
    {:ok, view, _html} = live(recycle(conn), "/")
    render_click(element(view, "button[phx-click='start_room']"))

    redirect =
      render_submit(element(view, "#run-smart_room"), %{
        "experiment_id" => "smart_room",
        "params" => %{}
      })

    {:ok, run_view, _html} = follow_redirect(redirect, recycle(conn), "/runs/run-1")
    html = render_click(element(run_view, "button[phx-click='cancel']"))
    assert html =~ "cancelled"
    refute html =~ "Approve this simulated Action"

    reset = get(recycle(conn), "/session/new")
    assert redirected_to(reset) == "/"

    previous = Application.get_env(:wotex_lab_workbench, :token_overrides)

    on_exit(fn ->
      if previous do
        Application.put_env(:wotex_lab_workbench, :token_overrides, previous)
      else
        Application.delete_env(:wotex_lab_workbench, :token_overrides)
      end
    end)

    Application.put_env(:wotex_lab_workbench, :token_overrides, %{
      "color-accent" => "#123456",
      "color-bg" => "red; color: transparent",
      "caller" => "#ffffff"
    })

    css = get(build_conn(), "/css/tokens.css") |> response(200)
    assert css =~ "--wl-color-accent: #123456"
    refute css =~ "transparent"
    refute css =~ "--wl-caller"

    hostile = %{
      build_conn()
      | host: "safe.test",
        req_headers: [{"host", "example.test; script-src *"}]
    }

    hostile = ContentSecurityPolicy.call(hostile, ContentSecurityPolicy.init([]))

    [policy] = get_resp_header(hostile, "content-security-policy")
    refute policy =~ "example.test;"

    assert length(Components.modules()) == 15
    assert Enum.map(Shell.items(), &elem(&1, 0)) == [:experiments, :things, :metrics, :evidence]
    assert :ok = WotexLabWorkbench.Application.config_change([], [], [])
  end
end
