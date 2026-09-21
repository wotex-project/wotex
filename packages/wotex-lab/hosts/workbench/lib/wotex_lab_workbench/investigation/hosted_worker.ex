defmodule WotexLabWorkbench.Investigation.HostedWorker do
  @moduledoc """
  One-request Escript entry point for hosted BeamLens investigations.

  The worker starts a fresh BeamLens tree containing only the hosted skill and
  its unavoidable empty log store. It receives no tenant credential, durable
  receiver credential or provider credential. Two expiring loopback
  capabilities are its only parent-host authorities: model completion and a
  server-bound durable metric query.
  """

  alias WotexLabWorkbench.Investigation.{
    BeamlensSupervisor,
    ContextStore,
    HostedSkill,
    OperatorRunner
  }

  @app :wotex_lab_workbench
  @schema "wotex-lab-hosted-investigation/v1"
  @max_request_bytes 32 * 1_024
  @max_priv_bytes 64 * 1_024 * 1_024
  @max_plain_depth 6
  @priv_apps ~w(baml_elixir beamlens puck)
  @loaded_apps ~w(baml_elixir beamlens puck)a
  @started_apps ~w(crypto public_key ssl inets telemetry luerl req)a
  @capability ~r/\A[A-Za-z0-9_-]{43}\z/
  @keys ~w(schema_version prompt current baseline provider_url query_url
           provider_capability query_capability result_capability timeout_ms)

  @doc false
  @spec main([String.t()]) :: no_return()
  def main(["--request", path]) do
    result =
      with {:ok, request} <- read_request(path),
           :ok <- prepare_priv(),
           :ok <- start_dependencies(),
           {:ok, result} <- investigate(request),
           {:ok, json} <- Jason.encode(result) do
        encoded = Base.url_encode64(json, padding: false)

        IO.binwrite(
          "WOTEX_HOSTED_WORKER_RESULT " <>
            request["result_capability"] <> " " <> encoded <> "\n"
        )

        :ok
      end

    case result do
      :ok -> System.halt(0)
      _ -> System.halt(64)
    end
  end

  def main(_), do: System.halt(64)

  @doc false
  @spec investigate(map()) :: {:ok, map()} | {:error, atom()}
  def investigate(request) do
    with {:ok, admitted} <- admit(request),
         :ok <- configure(admitted),
         {:ok, supervisor} <- start_tree(admitted),
         :ok <- ContextStore.put(admitted.current, admitted.baseline),
         {:ok, operator} <- operator() do
      try do
        result = OperatorRunner.run(operator, admitted.prompt, admitted.timeout_ms)
        {:ok, result(result)}
      after
        _ = Supervisor.stop(supervisor, :normal, 2_000)
      end
    else
      _ -> {:error, :invalid_hosted_investigation}
    end
  catch
    :exit, _ -> {:error, :hosted_investigation_failed}
  end

  defp read_request(path) when is_binary(path) do
    with true <- Path.type(path) == :absolute,
         {:ok, stat} <- File.lstat(path),
         true <- stat.type == :regular and stat.size in 1..@max_request_bytes,
         {:ok, bytes} <- File.read(path),
         :ok <- File.rm(path),
         {:ok, request} when is_map(request) <- Jason.decode(bytes) do
      {:ok, request}
    else
      _ -> {:error, :invalid_request_file}
    end
  end

  defp read_request(_), do: {:error, :invalid_request_file}

  defp admit(request) when is_map(request) do
    with true <- Enum.sort(Map.keys(request)) == Enum.sort(@keys),
         @schema <- request["schema_version"],
         prompt when is_binary(prompt) and byte_size(prompt) in 1..4_096 <- request["prompt"],
         true <- String.trim(prompt) != "",
         true <- context?(request["current"]) and context?(request["baseline"]),
         true <- loopback?(request["provider_url"], "/api/internal/beamlens/v1"),
         true <-
           loopback?(
             request["query_url"],
             "/api/internal/hosted-investigation/v1/query"
           ),
         true <- capability?(request["provider_capability"]),
         true <- capability?(request["query_capability"]),
         true <- capability?(request["result_capability"]),
         timeout when is_integer(timeout) and timeout in 1_000..29_000 <- request["timeout_ms"] do
      {:ok,
       %{
         prompt: prompt,
         current: request["current"],
         baseline: request["baseline"],
         provider_url: request["provider_url"],
         query_url: request["query_url"],
         provider_capability: request["provider_capability"],
         query_capability: request["query_capability"],
         timeout_ms: timeout
       }}
    else
      _ -> {:error, :invalid_hosted_investigation}
    end
  end

  defp configure(request) do
    Application.put_env(@app, :hosted_query_url, request.query_url, persistent: false)

    Application.put_env(
      @app,
      :hosted_query_capability,
      request.query_capability,
      persistent: false
    )

    :ok
  end

  defp start_tree(request) do
    registry = %{
      primary: "WotexLabHostedInvestigation",
      clients: [
        %{
          name: "WotexLabHostedInvestigation",
          provider: "openai-generic",
          options: %{
            api_key: request.provider_capability,
            base_url: request.provider_url,
            model: "wotex-lab-investigation"
          }
        }
      ]
    }

    Supervisor.start_link(
      [
        {ContextStore, []},
        {BeamlensSupervisor, client_registry: registry, skill: HostedSkill}
      ],
      strategy: :one_for_one
    )
  end

  defp start_dependencies do
    with :ok <- load_applications(@loaded_apps) do
      start_applications(@started_apps)
    end
  end

  defp load_applications(apps) do
    Enum.reduce_while(apps, :ok, fn app, :ok ->
      case Application.load(app) do
        :ok -> {:cont, :ok}
        {:error, {:already_loaded, ^app}} -> {:cont, :ok}
        {:error, _} -> {:halt, {:error, :dependency_load_failed}}
      end
    end)
  end

  defp start_applications(apps) do
    Enum.reduce_while(apps, :ok, fn app, :ok ->
      case Application.ensure_all_started(app) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} -> {:halt, {:error, :dependency_start_failed}}
      end
    end)
  end

  defp prepare_priv do
    with {:ok, parts} <- :escript.extract(:escript.script_name(), []),
         archive when is_binary(archive) <- Keyword.get(parts, :archive),
         {:ok, files} <- :zip.extract(archive, [:memory]),
         selected <- Enum.filter(files, &priv_entry?/1),
         true <- selected != [] and length(selected) <= 64,
         true <-
           Enum.sum(Enum.map(selected, fn {_, bytes} -> byte_size(bytes) end)) <= @max_priv_bytes,
         :ok <- write_priv(selected) do
      Enum.each(@priv_apps, fn app ->
        File.mkdir_p!(Path.join([File.cwd!(), app, "ebin"]))
        true = Code.prepend_path(Path.join([File.cwd!(), app, "ebin"]))
      end)

      :ok
    else
      _ -> {:error, :worker_priv_unavailable}
    end
  end

  defp priv_entry?({name, bytes}) when is_list(name) and is_binary(bytes) do
    case String.split(to_string(name), "/") do
      [app, "priv" | rest] ->
        app in @priv_apps and rest != [] and
          Enum.all?(rest, &(&1 not in ["", ".", ".."] and byte_size(&1) <= 255))

      _ ->
        false
    end
  end

  defp priv_entry?(_), do: false

  defp write_priv(files) do
    Enum.reduce_while(files, :ok, fn {name, bytes}, :ok ->
      path = Path.join(File.cwd!(), to_string(name))

      with :ok <- File.mkdir_p(Path.dirname(path)),
           :ok <- File.write(path, bytes, [:exclusive, :binary]),
           :ok <- File.chmod(path, if(String.ends_with?(path, ".so"), do: 0o700, else: 0o600)) do
        {:cont, :ok}
      else
        _ -> {:halt, {:error, :worker_priv_unavailable}}
      end
    end)
  end

  defp operator do
    case Registry.lookup(Beamlens.OperatorRegistry, HostedSkill) do
      [{pid, _}] -> {:ok, pid}
      _ -> {:error, :operator_unavailable}
    end
  end

  defp result({:ok, notifications}) do
    %{
      "status" => "ok",
      "notifications" => plain(notifications),
      "evidence" => ContextStore.evidence(),
      "usage" => ContextStore.usage()
    }
  end

  defp result({:error, reason}) do
    %{
      "status" => "error",
      "code" => safe_code(reason),
      "evidence" => ContextStore.evidence(),
      "usage" => ContextStore.usage()
    }
  end

  defp result(_),
    do: %{"status" => "error", "code" => "provider_failure", "evidence" => []}

  defp safe_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_code(_), do: "provider_failure"

  defp plain(value), do: plain(value, 0)
  defp plain(_, depth) when depth > @max_plain_depth, do: "…"
  defp plain(%DateTime{} = value, _), do: DateTime.to_iso8601(value)
  defp plain(%MapSet{} = value, depth), do: plain(MapSet.to_list(value), depth + 1)
  defp plain(%_{} = value, depth), do: plain(Map.from_struct(value), depth + 1)

  defp plain(value, depth) when is_map(value) do
    value
    |> Enum.take(64)
    |> Map.new(fn {key, inner} -> {to_string(key), plain(inner, depth + 1)} end)
  end

  defp plain(value, depth) when is_list(value),
    do: Enum.map(Enum.take(value, 64), &plain(&1, depth + 1))

  defp plain(value, depth) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.take(64)
    |> Enum.map(&plain(&1, depth + 1))
  end

  defp plain(value, _) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: Atom.to_string(value)

  defp plain(value, _)
       when is_pid(value) or is_reference(value) or is_function(value) or is_port(value),
       do: "opaque"

  defp plain(value, _), do: value

  defp context?(nil), do: true

  defp context?(value) when is_map(value) do
    case Jason.encode(value) do
      {:ok, encoded} -> byte_size(encoded) <= 8 * 1_024
      _ -> false
    end
  end

  defp context?(_), do: false

  defp capability?(value),
    do: is_binary(value) and Regex.match?(@capability, value)

  defp loopback?(url, prefix) when is_binary(url) do
    case URI.parse(url) do
      %URI{
        scheme: "http",
        host: host,
        port: port,
        path: path,
        userinfo: nil,
        query: nil,
        fragment: nil
      }
      when host in ["127.0.0.1", "localhost", "::1"] and is_integer(port) ->
        path == prefix or String.starts_with?(path || "", prefix <> "/")

      _ ->
        false
    end
  end

  defp loopback?(_, _), do: false
end
