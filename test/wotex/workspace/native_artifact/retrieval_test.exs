defmodule Wotex.Workspace.NativeArtifact.RetrievalTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.NativeArtifact.Archive
  alias Wotex.Workspace.NativeArtifact.Cache
  alias Wotex.Workspace.NativeArtifact.Descriptor
  alias Wotex.Workspace.NativeArtifact.PayloadManifest
  alias Wotex.Workspace.NativeArtifact.Retrieval
  alias Wotex.Workspace.NativeArtifact.Retrieval.Limits
  alias WotexWorkspace.Fixtures
  alias WotexWorkspace.NativeArtifactArchiveFixture, as: Tar

  @build_identity String.duplicate("a", 64)

  setup context do
    root = Fixtures.tmp_dir(context)
    payload = Path.join(root, "payload")
    cache = Path.join(root, "cache")
    File.mkdir_p!(Path.join(payload, "bin"))
    Fixtures.write!(payload, "bin/tool", "retrieved payload\n")
    File.chmod!(Path.join(payload, "bin/tool"), 0o755)
    descriptor = descriptor([source("hosted", "origin.invalid")])
    archive = artifact_bytes(descriptor, payload)

    %{
      root: root,
      payload: payload,
      cache: cache,
      descriptor: descriptor,
      archive: archive,
      digest: sha256(archive)
    }
  end

  test "streams, independently hashes, verifies and adopts one declared source", context do
    parent = self()

    plug = fn conn ->
      send(parent, {:request, conn.host, conn.request_path})
      Plug.Conn.send_resp(conn, 200, context.archive)
    end

    assert {:ok, result} = retrieve(context, plug: plug)
    assert result.source == "hosted"
    assert result.selected_url =~ "origin.invalid/native/production/linux-x86-64/"
    assert result.delivery_path == [result.selected_url]
    assert result.transport_sha256 == context.digest
    assert result.transport_size == byte_size(context.archive)
    assert result.entry.manifest.build_identity == @build_identity
    assert_receive {:request, "origin.invalid", request_path}
    assert request_path =~ @build_identity
    assert downloads_empty?(context.cache)
  end

  test "strips authorization across origins and redacts redirect queries", context do
    parent = self()

    plug = fn conn ->
      authorization = Plug.Conn.get_req_header(conn, "authorization")
      send(parent, {:authorization, conn.host, authorization})

      case conn.host do
        "origin.invalid" ->
          conn
          |> Plug.Conn.put_resp_header(
            "location",
            "https://cdn.invalid/release/artifact.tar?signature=not-for-evidence"
          )
          |> Plug.Conn.send_resp(302, "redirect")

        "cdn.invalid" ->
          Plug.Conn.send_resp(conn, 200, context.archive)
      end
    end

    assert {:ok, result} =
             retrieve(context,
               plug: plug,
               source: "hosted",
               authorization: "Bearer private-value"
             )

    assert_receive {:authorization, "origin.invalid", ["Bearer private-value"]}
    assert_receive {:authorization, "cdn.invalid", []}

    assert result.delivery_path == [
             result.selected_url,
             "https://cdn.invalid/release/artifact.tar"
           ]

    refute inspect(result) =~ "private-value"
    refute inspect(result) =~ "not-for-evidence"
  end

  test "aggregates bounded source failures without leaking response bodies", context do
    descriptor =
      descriptor([
        source("primary", "primary.invalid"),
        source("mirror", "mirror.invalid")
      ])

    plug = fn conn ->
      status = if conn.host == "primary.invalid", do: 404, else: 503
      Plug.Conn.send_resp(conn, status, "secret response body")
    end

    assert {:error, errors} = retrieve(%{context | descriptor: descriptor}, plug: plug)
    assert errors == ["primary: server returned HTTP 404", "mirror: server returned HTTP 503"]
    refute Enum.join(errors) =~ "secret"
    assert downloads_empty?(context.cache)
  end

  test "bounds final and error responses while removing partial stages", context do
    chunked = fn conn ->
      conn = Plug.Conn.send_chunked(conn, 200)
      {:ok, conn} = Plug.Conn.chunk(conn, "1234")
      {:ok, conn} = Plug.Conn.chunk(conn, "5678")
      conn
    end

    limits = %Limits{response_bytes: 6, error_body_bytes: 4, redirects: 1, timeout_ms: 1_000}
    assert {:error, [message]} = retrieve(context, plug: chunked, limits: limits)
    assert message =~ "response exceeds 6 bytes"
    assert downloads_empty?(context.cache)

    error_plug = fn conn -> Plug.Conn.send_resp(conn, 404, "oversized failure body") end
    assert {:error, [message]} = retrieve(context, plug: error_plug, limits: limits)
    assert message =~ "response exceeds 4 bytes"
    assert downloads_empty?(context.cache)
  end

  test "rejects a digest mismatch and a transport interruption without adoption", context do
    plug = fn conn -> Plug.Conn.send_resp(conn, 200, context.archive) end

    assert {:error, [message]} =
             retrieve(%{context | digest: String.duplicate("b", 64)}, plug: plug)

    assert message =~ "transport digest mismatch"
    refute cache_entry?(context.cache)
    assert downloads_empty?(context.cache)

    interrupted = fn conn -> Req.Test.transport_error(conn, :closed) end
    assert {:error, [message]} = retrieve(context, plug: interrupted)
    assert message =~ "request failed"
    refute cache_entry?(context.cache)
    assert downloads_empty?(context.cache)
  end

  test "preserves an earlier valid entry when a retrieved payload is invalid", context do
    valid = fn conn -> Plug.Conn.send_resp(conn, 200, context.archive) end
    assert {:ok, original} = retrieve(context, plug: valid)

    invalid_bytes = "not an artifact"
    invalid = fn conn -> Plug.Conn.send_resp(conn, 200, invalid_bytes) end

    assert {:error, [message]} =
             retrieve(%{context | digest: sha256(invalid_bytes)}, plug: invalid)

    assert message =~ "failed artifact verification"

    assert {:ok, retained} =
             Cache.inspect(
               context.cache,
               @build_identity,
               context.descriptor,
               "linux-x86-64"
             )

    assert retained.manifest.payload_identity == original.entry.manifest.payload_identity
  end

  test "bounds redirects and never follows a non-HTTPS target", context do
    loop = fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "https://origin.invalid/again")
      |> Plug.Conn.send_resp(302, "redirect")
    end

    limits = %Limits{redirects: 1, timeout_ms: 1_000}
    assert {:error, [message]} = retrieve(context, plug: loop, limits: limits)
    assert message =~ "redirect limit 1 exceeded"

    downgrade = fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "http://origin.invalid/artifact")
      |> Plug.Conn.send_resp(302, "redirect")
    end

    assert {:error, [message]} = retrieve(context, plug: downgrade)
    assert message =~ "redirect target is not HTTPS"
    assert downloads_empty?(context.cache)
  end

  test "requires a declared source and scopes credentials to an exact selection", context do
    no_sources = descriptor([])
    assert {:error, [message]} = retrieve(%{context | descriptor: no_sources})
    assert message =~ "declares no prebuilt sources"

    assert {:error, [message]} =
             retrieve(context, authorization: "Bearer private-value")

    assert message =~ "requires selecting one exact"

    assert {:error, [message]} = retrieve(context, source: "absent")
    assert message =~ "does not declare retrieval source"

    assert {:error, [message]} =
             retrieve(context, source: "hosted", authorization: "Bearer x\nInjected: y")

    assert message =~ "prohibited line break"
  end

  test "refuses symlinked cache and download-staging roots", context do
    outside = Path.join(context.root, "outside")
    File.mkdir_p!(outside)
    File.ln_s!(outside, context.cache)

    assert {:error, [message]} = retrieve(context)
    assert message =~ "cache root is symlink"

    File.rm!(context.cache)
    File.mkdir_p!(context.cache)
    File.ln_s!(outside, Path.join(context.cache, "downloads"))

    assert {:error, [message]} = retrieve(context)
    assert message =~ "download staging root is symlink"
  end

  defp retrieve(context, opts \\ []) do
    Retrieval.retrieve_and_adopt(
      context.descriptor,
      "linux-x86-64",
      @build_identity,
      context.digest,
      context.cache,
      opts
    )
  end

  defp descriptor(sources) do
    %Descriptor{
      package: "native",
      profile: "production",
      kind: "executable",
      targets: [%{name: "linux-x86-64", status: :supported, reason: nil}],
      raw: %{
        "outputs" => [
          %{"path" => "bin/tool", "kind" => "file", "mode" => 0o755, "required" => true}
        ],
        "retrieval" => %{"sources" => sources}
      }
    }
  end

  defp source(name, host) do
    %{
      "name" => name,
      "url" => "https://#{host}/{package}/{profile}/{target}/{build_identity}/artifact.tar"
    }
  end

  defp artifact_bytes(descriptor, payload) do
    assert {:ok, manifest} =
             PayloadManifest.build(descriptor, "linux-x86-64", @build_identity, payload)

    assert {:ok, manifest_bytes} = PayloadManifest.encode(manifest)

    Tar.bytes([
      %{
        path: Archive.manifest_path(),
        kind: :file,
        content: manifest_bytes,
        mode: 0o644
      },
      %{
        path: "bin/tool",
        kind: :file,
        content: File.read!(Path.join(payload, "bin/tool")),
        mode: 0o755
      }
    ])
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp downloads_empty?(cache) do
    downloads = Path.join(cache, "downloads")
    File.dir?(downloads) and File.ls!(downloads) == []
  end

  defp cache_entry?(cache) do
    objects = Path.join(cache, "objects")
    File.dir?(objects) and File.ls!(objects) != []
  end
end
