defmodule WotexLabWorkbench.Test.GrafanaCohort do
  @moduledoc false

  # Disposable pinned GreptimeDB and Grafana containers for the separately
  # selected `WOTEX_LAB_GRAFANA=1` lane. Both join one private Docker network
  # created for the test, publish only an ephemeral IPv4-loopback port, keep no
  # named volume and carry CPU, memory and PID budgets. Grafana runs with a
  # generated administrator password, anonymous access and sign-up disabled,
  # and no reporting, update check, news feed or plugin preinstallation. All
  # containers and the network are removed in `on_exit`. Images are never
  # pulled by the lane. The helpers issue only the fixed API calls the import
  # cohort needs; no caller SQL is sent.

  @greptime "greptime/greptimedb:v1.1.4@sha256:9726587eac95d0360755254cd59a528dbf48abfdf268478aea6a644f62afe44c"
  @grafana "grafana/grafana:13.2.2@sha256:ac461fb352abc50da10a51c7d02462e9c05488f11f53f14b3ad79a8145f638a0"

  @type t :: %{
          network: String.t(),
          greptime: String.t(),
          greptime_url: String.t(),
          write_url: String.t(),
          grafana: String.t(),
          grafana_url: String.t(),
          password: String.t()
        }

  @doc false
  @spec start() :: t()
  def start do
    suffix = 6 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
    network = "wotex-lab-grafana-" <> suffix
    greptime = "wotex-lab-greptime-" <> suffix
    grafana = "wotex-lab-grafana-ui-" <> suffix
    password = 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    ExUnit.Callbacks.on_exit(fn -> halt([grafana, greptime], network) end)
    docker!(["network", "create", "--label", "wotex-lab-lane=grafana", network])

    docker!(
      container_args(greptime, network, "4000") ++
        [@greptime, "standalone", "start", "--http-addr", "0.0.0.0:4000"]
    )

    docker!(
      container_args(grafana, network, "3000") ++
        Enum.flat_map(grafana_environment(password), &["--env", &1]) ++ [@grafana]
    )

    greptime_url = "http://127.0.0.1:#{mapped_port(greptime, "4000", 100)}"
    grafana_url = "http://127.0.0.1:#{mapped_port(grafana, "3000", 100)}"
    :ok = await(greptime_url <> "/health", 600)
    :ok = await(grafana_url <> "/api/health", 1_200)

    %{
      network: network,
      greptime: greptime,
      greptime_url: greptime_url,
      write_url: greptime_url <> "/v1/prometheus/write",
      grafana: grafana,
      grafana_url: grafana_url,
      password: password
    }
  end

  @doc false
  @spec halt([String.t()], String.t()) :: :ok
  def halt(containers, network) do
    _ = System.cmd("docker", ["rm", "--force", "--volumes" | containers], stderr_to_stdout: true)
    _ = System.cmd("docker", ["network", "rm", network], stderr_to_stdout: true)
    :ok
  end

  @doc false
  @spec version(t()) :: String.t()
  def version(cohort) do
    %{status: 200, body: %{"version" => version}} = grafana(cohort, :get, "/api/health")
    version
  end

  @doc "Creates the Prometheus-compatible data source pointing at GreptimeDB on the private network."
  @spec create_datasource(t()) :: String.t()
  def create_datasource(cohort) do
    %{status: 200, body: %{"datasource" => %{"uid" => uid}}} =
      grafana(cohort, :post, "/api/datasources",
        json: %{
          name: "GreptimeDB Prometheus API",
          type: "prometheus",
          access: "proxy",
          url: "http://#{cohort.greptime}:4000/v1/prometheus",
          jsonData: %{httpMethod: "POST", timeInterval: "1s"}
        }
      )

    uid
  end

  @doc "Creates one folder so dashboards with the same title can coexist."
  @spec create_folder(t(), String.t()) :: String.t()
  def create_folder(cohort, title) do
    %{status: 200, body: %{"uid" => uid}} =
      grafana(cohort, :post, "/api/folders", json: %{title: title})

    uid
  end

  @doc "Imports exported dashboard JSON through Grafana's import API, binding the data source input."
  @spec import(t(), map(), String.t(), String.t()) :: Req.Response.t()
  def import(cohort, dashboard, datasource_uid, folder_uid) do
    grafana(cohort, :post, "/api/dashboards/import",
      json: %{
        dashboard: dashboard,
        overwrite: false,
        folderUid: folder_uid,
        inputs: [
          %{
            name: "DS_PROMETHEUS",
            type: "datasource",
            pluginId: "prometheus",
            value: datasource_uid
          }
        ]
      }
    )
  end

  @doc "Reads one stored dashboard model back from Grafana."
  @spec dashboard(t(), String.t()) :: map()
  def dashboard(cohort, uid) do
    %{status: 200, body: body} = grafana(cohort, :get, "/api/dashboards/uid/" <> uid)
    body
  end

  @doc "Executes one stored panel target through Grafana's data source query API."
  @spec query(t(), map(), pos_integer(), pos_integer()) :: Req.Response.t()
  def query(cohort, target, from_ms, to_ms) do
    grafana(cohort, :post, "/api/ds/query",
      json: %{
        from: Integer.to_string(from_ms),
        to: Integer.to_string(to_ms),
        queries: [
          Map.merge(target, %{
            "range" => true,
            "instant" => false,
            "intervalMs" => 5_000,
            "maxDataPoints" => 200
          })
        ]
      }
    )
  end

  defp grafana(cohort, method, path, options \\ []) do
    Req.request!(
      [
        method: method,
        url: cohort.grafana_url <> path,
        auth: {:basic, "admin:" <> cohort.password},
        retry: false,
        receive_timeout: 30_000
      ] ++ options
    )
  end

  defp grafana_environment(password) do
    [
      "GF_SECURITY_ADMIN_PASSWORD=" <> password,
      "GF_AUTH_ANONYMOUS_ENABLED=false",
      "GF_USERS_ALLOW_SIGN_UP=false",
      "GF_ANALYTICS_REPORTING_ENABLED=false",
      "GF_ANALYTICS_CHECK_FOR_UPDATES=false",
      "GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES=false",
      "GF_NEWS_NEWS_FEED_ENABLED=false",
      "GF_PLUGINS_PREINSTALL_DISABLED=true",
      "GF_LOG_LEVEL=warn"
    ]
  end

  defp container_args(name, network, port) do
    [
      "run",
      "--detach",
      "--pull",
      "never",
      "--name",
      name,
      "--label",
      "wotex-lab-lane=grafana",
      "--network",
      network,
      "--cpus",
      "2",
      "--memory",
      "1g",
      "--memory-swap",
      "1g",
      "--pids-limit",
      "512",
      "--publish",
      "127.0.0.1::" <> port
    ]
  end

  defp docker!(args) do
    case System.cmd("docker", args, stderr_to_stdout: true) do
      {output, 0} -> output
      {output, status} -> raise "docker #{hd(args)} failed (#{status}): #{output}"
    end
  end

  defp mapped_port(container, _, 0), do: raise("#{container} published no mapped port")

  defp mapped_port(container, port, attempts) do
    with {output, 0} <- System.cmd("docker", ["port", container, port], stderr_to_stdout: true),
         [mapping | _] <- String.split(String.trim(output), "\n", trim: true) do
      mapping |> String.split(":") |> List.last() |> String.to_integer()
    else
      _ ->
        Process.sleep(100)
        mapped_port(container, port, attempts - 1)
    end
  end

  defp await(url, 0), do: raise("#{url} never became healthy")

  defp await(url, attempts) do
    case Req.get(url, retry: false, receive_timeout: 1_000) do
      {:ok, %{status: 200}} ->
        :ok

      _ ->
        Process.sleep(100)
        await(url, attempts - 1)
    end
  end
end
