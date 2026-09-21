defmodule WotexLabWorkbench.HostedCommandTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.Investigation.HostedCommand
  alias WotexLabWorkbench.Observability.Supervisor, as: ObservabilitySupervisor

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "wotex-hosted-command-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    source = System.find_executable("escript") || raise "escript is unavailable"

    path_keys = %{"runner" => :runner, "runtime" => :runtime, "worker" => :worker}

    paths =
      for name <- ~w(runner runtime worker), into: %{} do
        path = Path.join(root, name)
        File.cp!(source, path)
        File.chmod!(path, if(name == "worker", do: 0o600, else: 0o700))
        {Map.fetch!(path_keys, name), path}
      end

    config = [
      runner: paths.runner,
      runner_sha256: digest(paths.runner),
      runtime: paths.runtime,
      runtime_sha256: digest(paths.runtime),
      worker: paths.worker,
      worker_sha256: digest(paths.worker),
      work_root: root,
      provider_url: "http://127.0.0.1:4000/api/internal/beamlens/v1",
      query_url: "http://127.0.0.1:4000/api/internal/hosted-investigation/v1/query",
      timeout_ms: 10_000
    ]

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, paths: paths, config: config}
  end

  test "configuration verifies exact regular artifacts and loopback bridges", %{config: config} do
    assert {:ok, admitted} = HostedCommand.configure(config)
    assert admitted == config

    for invalid <- [
          Keyword.put(config, :runner_sha256, "sha256:" <> String.duplicate("0", 64)),
          Keyword.put(config, :worker_sha256, "short"),
          Keyword.put(config, :provider_url, "https://example.invalid/api/internal/beamlens/v1"),
          Keyword.put(config, :query_url, "http://user:secret@127.0.0.1:4000/api"),
          Keyword.put(config, :timeout_ms, 30_001),
          Keyword.put(config, :unknown, true)
        ] do
      assert {:error, %Error{code: :invalid_hosted_worker}} = HostedCommand.configure(invalid)
    end
  end

  test "symlinks and writable artifacts are never admitted", %{
    root: root,
    paths: paths,
    config: config
  } do
    link = Path.join(root, "runner-link")
    File.ln_s!(paths.runner, link)

    linked_config = Keyword.put(config, :runner, link)

    assert {:error, %Error{code: :invalid_hosted_worker}} =
             HostedCommand.configure(linked_config)

    File.chmod!(paths.worker, 0o622)
    assert {:error, %Error{code: :invalid_hosted_worker}} = HostedCommand.configure(config)
    File.chmod!(paths.worker, 0o600)

    directory_link = Path.join(root, "work-link")
    File.ln_s!(root, directory_link)
    linked_config = Keyword.put(config, :work_root, directory_link)

    assert {:error, %Error{code: :invalid_hosted_worker}} =
             HostedCommand.configure(linked_config)
  end

  test "run validates request shape before starting any process", %{config: config} do
    assert {:error, %Error{code: :invalid_hosted_request}} = HostedCommand.run(config, [])

    assert {:error, %Error{code: :invalid_hosted_request}} =
             HostedCommand.run(config, %{"body" => String.duplicate("x", 33 * 1_024)})
  end

  test "the hosted cohort refuses to start without a durable reader", %{
    paths: paths,
    config: config
  } do
    hosted = [
      tenants: [%{id: "tenant", instance: "metrics", token_digest: <<0::256>>}],
      listener: [
        port: 0,
        ip: {127, 0, 0, 1},
        certfile: paths.runtime,
        keyfile: paths.worker
      ],
      command: config,
      provider: :ollama
    ]

    assert {:error, %Error{code: :hosted_access_requires_durable_query}} =
             ObservabilitySupervisor.start_link(hosted: hosted)
  end

  defp digest(path),
    do: "sha256:" <> (:crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower))
end
