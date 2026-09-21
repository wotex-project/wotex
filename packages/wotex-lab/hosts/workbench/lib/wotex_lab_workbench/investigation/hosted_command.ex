defmodule WotexLabWorkbench.Investigation.HostedCommand do
  @moduledoc """
  Verifies and invokes the isolated hosted-investigation artifacts.

  The native custodian, Escript runtime and worker archive are each admitted by
  an absolute path and full SHA-256 digest. Every request runs from a new
  private directory with a scrubbed environment. The native custodian owns the
  worker process group, bounds wall time, output, resident memory, descendants
  and file descriptors, and reports success only after cleanup.
  """

  alias Wotex.Lab.{Error, Options}

  @digest ~r/\Asha256:[0-9a-f]{64}\z/
  @max_request_bytes 32 * 1_024
  @max_result_bytes 256 * 1_024
  @max_artifact_bytes 256 * 1_024 * 1_024
  @runner_header ~r/\AWOTEX_HOSTED_RUNNER cleanup=ok outcome=exit status=0 output_bytes=(\d{1,7})\r?\n/
  @keys [
    :runner,
    :runner_sha256,
    :runtime,
    :runtime_sha256,
    :worker,
    :worker_sha256,
    :work_root,
    :provider_url,
    :query_url,
    :timeout_ms
  ]

  @type t :: keyword()

  @doc "Validates immutable worker inputs without starting a process."
  @spec configure(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def configure(opts) do
    with :ok <- validate_options(opts),
         {:ok, runner} <- artifact(opts, :runner, :runner_sha256, true),
         {:ok, runtime} <- artifact(opts, :runtime, :runtime_sha256, true),
         {:ok, worker} <- artifact(opts, :worker, :worker_sha256, false),
         {:ok, work_root} <- directory(Keyword.get(opts, :work_root)),
         true <- loopback_url?(Keyword.get(opts, :provider_url), "/api/internal/beamlens/v1"),
         true <-
           loopback_url?(
             Keyword.get(opts, :query_url),
             "/api/internal/hosted-investigation/v1/query"
           ),
         timeout when is_integer(timeout) and timeout in 1_000..30_000 <-
           Keyword.get(opts, :timeout_ms, 30_000) do
      {:ok,
       [
         runner: runner.path,
         runner_sha256: runner.digest,
         runtime: runtime.path,
         runtime_sha256: runtime.digest,
         worker: worker.path,
         worker_sha256: worker.digest,
         work_root: work_root,
         provider_url: Keyword.fetch!(opts, :provider_url),
         query_url: Keyword.fetch!(opts, :query_url),
         timeout_ms: timeout
       ]}
    else
      {:error, _} = error -> error
      _ -> invalid(:invalid_hosted_worker, "hosted investigation worker is invalid")
    end
  end

  defp validate_options(opts) do
    case Options.validate(opts, @keys) do
      :ok -> :ok
      {:error, _} -> invalid(:invalid_hosted_worker, "hosted investigation options are invalid")
    end
  end

  @doc "Runs one admitted worker request and returns its bounded JSON result."
  @spec run(t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def run(config, request) when is_list(config) and is_map(request) do
    result_capability = capability()
    request = Map.put(request, "result_capability", result_capability)

    with {:ok, config} <- configure(config),
         {:ok, encoded} <- Jason.encode(request),
         true <- byte_size(encoded) in 1..@max_request_bytes,
         {:ok, directory} <- private_directory(Keyword.fetch!(config, :work_root)) do
      try do
        request_path = Path.join(directory, "request.json")

        with :ok <- write_request(request_path, encoded),
             {:ok, output} <- execute(config, directory, request_path) do
          decode(output, result_capability)
        end
      after
        remove_private(directory, Keyword.fetch!(config, :work_root))
      end
    else
      {:error, _} = error -> error
      _ -> invalid(:invalid_hosted_request, "hosted investigation request is invalid")
    end
  end

  def run(_, _),
    do: invalid(:invalid_hosted_request, "hosted investigation request is invalid")

  defp execute(config, directory, request_path) do
    runner = Keyword.fetch!(config, :runner)
    runtime = Keyword.fetch!(config, :runtime)
    worker = Keyword.fetch!(config, :worker)
    timeout = Keyword.fetch!(config, :timeout_ms)

    args = [
      "--wall-ms",
      Integer.to_string(timeout),
      "--output-bytes",
      Integer.to_string(@max_result_bytes),
      "--work-dir",
      directory,
      "--temp-dir",
      directory,
      "--",
      runtime,
      worker,
      "--request",
      request_path
    ]

    case System.cmd(runner, args,
           cd: directory,
           env: scrubbed_environment(directory),
           stderr_to_stdout: true
         ) do
      {output, 0} when byte_size(output) <= @max_result_bytes + 512 -> {:ok, output}
      _ -> unavailable(:hosted_worker_failed)
    end
  rescue
    _ -> unavailable(:hosted_worker_failed)
  end

  defp decode(output, result_capability) do
    with [header, claimed] <- Regex.run(@runner_header, output),
         payload <- String.replace_prefix(output, header, ""),
         {bytes, ""} <- Integer.parse(claimed),
         true <- bytes == byte_size(payload),
         marker = "WOTEX_HOSTED_WORKER_RESULT " <> result_capability <> " ",
         lines = :binary.split(payload, "\n", [:global]),
         [<<>>, line | _] <- Enum.reverse(lines),
         line <- String.trim_trailing(line, "\r"),
         true <- String.starts_with?(line, marker),
         true <- length(:binary.matches(payload, marker)) == 1,
         encoded <- binary_part(line, byte_size(marker), byte_size(line) - byte_size(marker)),
         true <- Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, encoded),
         {:ok, json} <- Base.url_decode64(encoded, padding: false),
         true <- byte_size(json) <= @max_result_bytes,
         {:ok, result} when is_map(result) <- Jason.decode(json) do
      {:ok, result}
    else
      _ -> unavailable(:invalid_hosted_worker_result)
    end
  end

  defp artifact(opts, path_key, digest_key, executable?) do
    path = Keyword.get(opts, path_key)
    digest = Keyword.get(opts, digest_key)

    with true <- is_binary(path) and Path.type(path) == :absolute,
         true <- is_binary(digest) and Regex.match?(@digest, digest),
         {:ok, before} <- File.lstat(path),
         true <- before.type == :regular and before.size in 1..@max_artifact_bytes,
         true <- not executable? or executable_mode?(before.mode),
         true <- Bitwise.band(before.mode, 0o022) == 0,
         {:ok, actual} <- file_digest(path),
         true <- actual == digest,
         {:ok, after_stat} <- File.lstat(path),
         true <- stable?(before, after_stat) do
      {:ok, %{path: path, digest: digest}}
    else
      _ -> invalid(:invalid_hosted_worker, "hosted investigation artifact is invalid")
    end
  end

  defp file_digest(path) do
    with {:ok, file} <- File.open(path, [:read, :binary]) do
      try do
        digest_stream(file, :crypto.hash_init(:sha256), 0)
      after
        File.close(file)
      end
    end
  end

  defp digest_stream(file, context, size) do
    case IO.binread(file, 64 * 1_024) do
      :eof ->
        digest = Base.encode16(:crypto.hash_final(context), case: :lower)
        {:ok, "sha256:" <> digest}

      bytes when is_binary(bytes) and size + byte_size(bytes) <= @max_artifact_bytes ->
        digest_stream(file, :crypto.hash_update(context, bytes), size + byte_size(bytes))

      _ ->
        {:error, :artifact_too_large}
    end
  end

  defp directory(path) when is_binary(path) do
    with true <- Path.type(path) == :absolute,
         {:ok, before} <- File.lstat(path),
         true <- before.type == :directory and Bitwise.band(before.mode, 0o077) == 0,
         {:ok, after_stat} <- File.lstat(path),
         true <- stable?(before, after_stat) do
      {:ok, path}
    else
      _ -> invalid(:invalid_hosted_worker, "hosted work root is invalid")
    end
  end

  defp directory(_), do: invalid(:invalid_hosted_worker, "hosted work root is invalid")

  defp private_directory(root) do
    name =
      ".wotex-hosted-" <>
        Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

    path = Path.join(root, name)

    case File.mkdir(path) do
      :ok ->
        with :ok <- File.chmod(path, 0o700), do: {:ok, path}

      {:error, :eexist} ->
        private_directory(root)

      _ ->
        unavailable(:hosted_worker_unavailable)
    end
  end

  defp write_request(path, bytes) do
    with {:ok, file} <- File.open(path, [:write, :binary, :exclusive]),
         :ok <- IO.binwrite(file, bytes),
         :ok <- File.close(file),
         :ok <- File.chmod(path, 0o600) do
      :ok
    else
      _ -> unavailable(:hosted_worker_unavailable)
    end
  end

  defp remove_private(path, root) do
    prefix = Path.join(root, ".wotex-hosted-")

    if String.starts_with?(path, prefix) and Path.dirname(path) == root do
      _ = File.rm_rf(path)
    end

    :ok
  end

  defp scrubbed_environment(directory) do
    removed = Map.new(System.get_env(), fn {key, _} -> {key, nil} end)

    removed
    |> Map.merge(%{
      "HOME" => directory,
      "TMPDIR" => directory,
      "LANG" => "C.UTF-8",
      "LC_ALL" => "C.UTF-8"
    })
    |> Enum.sort()
  end

  defp loopback_url?(url, prefix) when is_binary(url) do
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

  defp loopback_url?(_, _), do: false

  defp stable?(left, right),
    do:
      left.type == right.type and left.size == right.size and left.inode == right.inode and
        left.major_device == right.major_device and left.minor_device == right.minor_device and
        left.mode == right.mode and left.mtime == right.mtime and left.ctime == right.ctime

  defp executable_mode?(mode), do: Bitwise.band(mode, 0o111) != 0

  defp capability,
    do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  defp unavailable(code),
    do: invalid(code, "hosted investigation worker is unavailable")

  defp invalid(code, message), do: {:error, Error.new(code, :hosted_investigation, message)}
end
