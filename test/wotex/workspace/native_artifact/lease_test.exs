defmodule Wotex.Workspace.NativeArtifact.LeaseTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.NativeArtifact.Lease
  alias WotexWorkspace.Fixtures

  @identity String.duplicate("a", 64)

  setup context do
    root = Fixtures.tmp_dir(context)
    cache = Path.join(root, "cache")
    File.mkdir_p!(cache)
    %{cache: cache, root: root}
  end

  test "grants one exact lease and bounds a competing wait", context do
    assert {:ok, lease} = Lease.acquire(context.cache, @identity, wait_ms: 50, ttl_ms: 1_000)
    assert Lease.valid?(lease)
    assert Lease.active?(context.cache, @identity)

    task =
      Task.async(fn ->
        Lease.acquire(context.cache, @identity, wait_ms: 10, ttl_ms: 1_000)
      end)

    assert {:error, message} = Task.await(task)
    assert message =~ "timed out waiting"

    assert :ok = Lease.release(lease)
    refute Lease.valid?(lease)
    refute Lease.active?(context.cache, @identity)
  end

  test "retires an expired lease and rejects the former owner", context do
    assert {:ok, first} = Lease.acquire(context.cache, @identity, wait_ms: 50, ttl_ms: 5)
    Process.sleep(15)

    assert {:ok, second} = Lease.acquire(context.cache, @identity, wait_ms: 50, ttl_ms: 1_000)
    refute Lease.valid?(first)
    assert Lease.valid?(second)
    assert {:error, "lease ownership was lost"} = Lease.release(first)
    assert :ok = Lease.release(second)
  end

  test "fails closed for malformed records and unsafe roots", context do
    lease_directory = Path.join(context.cache, "leases")
    File.mkdir_p!(lease_directory)
    File.write!(Path.join(lease_directory, @identity <> ".json"), "not-json")

    assert Lease.active?(context.cache, @identity)
    assert {:error, message} = Lease.acquire(context.cache, @identity, wait_ms: 10)
    assert message =~ "invalid lease JSON"

    outside = Path.join(context.root, "outside")
    linked_cache = Path.join(context.root, "linked-cache")
    File.mkdir_p!(outside)
    File.mkdir_p!(linked_cache)
    File.ln_s!(outside, Path.join(linked_cache, "leases"))

    assert {:error, message} = Lease.acquire(linked_cache, @identity)
    assert message =~ "symlink"

    root_link = Path.join(context.root, "root-link")
    File.ln_s!(context.cache, root_link)
    assert {:error, message} = Lease.acquire(root_link, @identity)
    assert message =~ "cache root is symlink"
  end

  test "requires full identities and positive bounded timing", context do
    assert {:error, message} = Lease.acquire(context.cache, "abc")
    assert message =~ "full lowercase SHA-256"

    assert {:error, message} = Lease.acquire(context.cache, @identity, wait_ms: 0)
    assert message =~ "wait_ms"

    assert {:error, message} = Lease.acquire(context.cache, @identity, ttl_ms: 86_400_001)
    assert message =~ "ttl_ms"
  end
end
