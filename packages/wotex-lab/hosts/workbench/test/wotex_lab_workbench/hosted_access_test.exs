defmodule WotexLabWorkbench.HostedAccessTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.Observability.{DurableReader, HostedAccess}

  @token "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  @other_token "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

  test "tenant documents are exact, digest-only and distinct from every other credential" do
    assert {:ok, [tenant]} = HostedAccess.admit(document(@token), [])
    assert tenant.id == "tenant-a" and tenant.instance == "metrics-a"
    assert tenant.token_digest == :crypto.hash(:sha256, @token)
    refute inspect(tenant) =~ @token

    assert {:error, %Error{code: :invalid_hosted_tenants}} =
             HostedAccess.admit(document(@token), [@token])

    for invalid <- [
          Map.put(document(@token), "unknown", true),
          Map.put(document(@token), "schema_version", "v2"),
          %{"schema_version" => "wotex-lab-hosted-tenants/v1", "tenants" => []},
          duplicate(document(@token), "id", "tenant-a"),
          duplicate(document(@token), "instance", "metrics-a"),
          duplicate(document(@token), "token_sha256", digest(@token)),
          put_in(document(@token), ["tenants", Access.at(0), "token_sha256"], "sha256:BAD"),
          put_in(document(@token), ["tenants", Access.at(0), "id"], "Tenant A"),
          update_in(document(@token)["tenants"], &List.duplicate(hd(&1), 65))
        ] do
      assert {:error, %Error{code: :invalid_hosted_tenants}} = HostedAccess.admit(invalid, [])
    end
  end

  test "file loading is bounded, absolute and rejects reserved credentials" do
    root = temporary_directory()
    on_exit(fn -> File.rm_rf!(root) end)
    path = Path.join(root, "tenants.json")
    File.write!(path, Jason.encode!(document(@token)))
    File.chmod!(path, 0o600)

    assert {:ok, [_]} = HostedAccess.load(path)
    assert {:error, %Error{code: :invalid_hosted_tenants}} = HostedAccess.load("tenants.json")

    assert {:error, %Error{code: :invalid_hosted_tenants}} =
             HostedAccess.load(path, [@token])

    link = Path.join(root, "tenants-link.json")
    File.ln_s!(path, link)
    assert {:error, %Error{code: :invalid_hosted_tenants}} = HostedAccess.load(link)

    File.chmod!(path, 0o644)
    assert {:error, %Error{code: :invalid_hosted_tenants}} = HostedAccess.load(path)
    File.chmod!(path, 0o600)
    File.write!(path, String.duplicate("x", 65_537))
    assert {:error, %Error{code: :invalid_hosted_tenants}} = HostedAccess.load(path)
  end

  test "leases are owner-bound with separate query and investigation concurrency" do
    start_access()
    assert {:error, %Error{code: :hosted_unauthorized}} = HostedAccess.open(@other_token, :query)
    assert {:error, %Error{code: :hosted_unauthorized}} = HostedAccess.open(@token, :other)

    assert {:ok, first} = HostedAccess.open(@token, :query)
    assert {:ok, second} = HostedAccess.open(@token, :query)
    assert first.instance == "metrics-a" and is_function(first.durable, 1)

    assert {:error, %Error{code: :tenant_concurrency}} = HostedAccess.open(@token, :query)

    task = Task.async(fn -> HostedAccess.release(first.lease) end)
    assert :ok = Task.await(task)
    assert HostedAccess.stats().active_queries == 2
    assert :ok = HostedAccess.release(first.lease)
    assert HostedAccess.stats().active_queries == 1

    assert {:ok, investigation} = HostedAccess.open(@token, :investigation)

    assert {:error, %Error{code: :tenant_concurrency}} =
             HostedAccess.open(@token, :investigation)

    assert :ok = HostedAccess.release(second.lease)
    assert :ok = HostedAccess.release(investigation.lease)
    assert HostedAccess.stats().active_queries == 0
    assert HostedAccess.stats().active_investigations == 0

    state = :erlang.term_to_binary(:sys.get_state(HostedAccess))
    assert :binary.match(state, @token) == :nomatch
  end

  test "owner death releases capacity and the fixed rate window is fail-closed" do
    start_access()
    parent = self()

    owner =
      spawn(fn ->
        send(parent, {:opened, HostedAccess.open(@token, :investigation)})
        Process.sleep(:infinity)
      end)

    assert_receive {:opened, {:ok, _}}, 1_000
    assert HostedAccess.stats().active_investigations == 1
    Process.exit(owner, :kill)
    eventually(fn -> HostedAccess.stats().active_investigations == 0 end)

    for _ <- 1..60 do
      assert {:ok, lease} = HostedAccess.open(@token, :query)
      assert :ok = HostedAccess.release(lease.lease)
    end

    assert {:error, %Error{code: :tenant_rate_limited}} = HostedAccess.open(@token, :query)
  end

  defp start_access do
    {:ok, durable} = DurableReader.configure("http://127.0.0.1:4000", nil)
    {:ok, tenants} = HostedAccess.admit(document(@token), [])
    start_supervised!({HostedAccess, tenants: tenants, durable: durable})
  end

  defp document(token) do
    %{
      "schema_version" => "wotex-lab-hosted-tenants/v1",
      "tenants" => [
        %{"id" => "tenant-a", "instance" => "metrics-a", "token_sha256" => digest(token)}
      ]
    }
  end

  defp duplicate(document, key, value) do
    entry = %{"id" => "tenant-b", "instance" => "metrics-b", "token_sha256" => digest(@other_token)}
    update_in(document["tenants"], &[Map.put(entry, key, value) | &1])
  end

  defp digest(token),
    do: "sha256:" <> (:crypto.hash(:sha256, token) |> Base.encode16(case: :lower))

  defp temporary_directory do
    path =
      Path.join(
        System.tmp_dir!(),
        "wotex-hosted-access-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(path)
    path
  end

  defp eventually(fun, attempts \\ 50)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_, 0), do: flunk("condition did not become true")
end
