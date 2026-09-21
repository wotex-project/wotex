defmodule Wotex.Workspace.NativeArtifact.Retrieval do
  @moduledoc """
  Bounded retrieval and adoption of one exact prebuilt native artifact.

  Only origins declared by the admitted descriptor are attempted. Response
  bytes stream into a private cache-adjacent stage, are checked against the
  caller's full transport digest, and then pass through the ordinary payload
  verifier and atomic cache adoption path.
  """

  alias Wotex.Workspace.NativeArtifact.Archive
  alias Wotex.Workspace.NativeArtifact.Cache
  alias Wotex.Workspace.NativeArtifact.Descriptor

  @digest ~r/^[0-9a-f]{64}$/

  defmodule Limits do
    @moduledoc "Bounds for one retrieval invocation."

    @type t :: %__MODULE__{
            response_bytes: pos_integer(),
            error_body_bytes: pos_integer(),
            redirects: non_neg_integer(),
            timeout_ms: pos_integer()
          }

    defstruct response_bytes: 536_870_912,
              error_body_bytes: 16_384,
              redirects: 5,
              timeout_ms: 60_000
  end

  defmodule Result do
    @moduledoc "One retrieved, verified and locally adopted artifact."

    @enforce_keys [
      :entry,
      :source,
      :selected_url,
      :delivery_path,
      :transport_sha256,
      :transport_size
    ]
    defstruct @enforce_keys
  end

  @doc "Retrieves one declared prebuilt and adopts it only after complete verification."
  @spec retrieve_and_adopt(
          Descriptor.t(),
          String.t(),
          String.t(),
          String.t(),
          Path.t(),
          keyword()
        ) :: {:ok, Result.t()} | {:error, [String.t()]}
  def retrieve_and_adopt(
        %Descriptor{} = descriptor,
        target,
        build_identity,
        expected_digest,
        cache_root,
        opts \\ []
      ) do
    limits = Keyword.get(opts, :limits, %Limits{})
    archive_limits = Keyword.get(opts, :archive_limits, %Archive.Limits{})
    source_name = Keyword.get(opts, :source)
    authorization = Keyword.get(opts, :authorization)

    with :ok <- validate_limits(limits),
         :ok <- validate_digest(build_identity, "build identity"),
         :ok <- validate_digest(expected_digest, "transport digest"),
         :ok <- validate_cache_root(cache_root),
         {:ok, %{status: :supported}} <- Descriptor.target(descriptor, target),
         :ok <- validate_authorization(authorization, source_name),
         {:ok, sources} <- select_sources(descriptor, source_name),
         {:ok, stage} <- create_stage(cache_root, build_identity) do
      try do
        deadline = System.monotonic_time(:millisecond) + limits.timeout_ms

        attempt_sources(sources, %{
          descriptor: descriptor,
          target: target,
          build_identity: build_identity,
          expected_digest: expected_digest,
          cache_root: cache_root,
          stage: stage,
          authorization: authorization,
          deadline: deadline,
          limits: limits,
          archive_limits: archive_limits,
          opts: opts
        })
      after
        remove_stage(stage)
      end
    else
      {:ok, %{status: :unsupported, reason: reason}} ->
        {:error, ["target #{target} is unsupported: #{reason}"]}

      {:error, messages} when is_list(messages) ->
        {:error, messages}

      {:error, message} ->
        {:error, [message]}
    end
  end

  defp attempt_sources(sources, context) do
    artifact = Path.join(context.stage, "artifact.tar")

    result =
      Enum.reduce_while(sources, {:error, []}, fn source, {:error, errors} ->
        url =
          expand_url(
            source["url"],
            context.descriptor,
            context.target,
            context.build_identity
          )

        case download(
               url,
               artifact,
               context.expected_digest,
               context.authorization,
               context.deadline,
               context.limits,
               context.opts
             ) do
          {:ok, delivery_path, size} ->
            case Cache.adopt(
                   artifact,
                   context.descriptor,
                   context.target,
                   context.build_identity,
                   context.cache_root,
                   limits: context.archive_limits
                 ) do
              {:ok, entry} ->
                retrieved = %Result{
                  entry: entry,
                  source: source["name"],
                  selected_url: redact_url(url),
                  delivery_path: delivery_path,
                  transport_sha256: context.expected_digest,
                  transport_size: size
                }

                {:halt, {:ok, retrieved}}

              {:error, adoption_errors} ->
                message =
                  "#{source["name"]}: downloaded object failed artifact verification: " <>
                    summarize_errors(adoption_errors)

                {:cont, {:error, [message | errors]}}
            end

          {:error, message} ->
            message = safe_message(message)
            {:cont, {:error, ["#{source["name"]}: #{message}" | errors]}}
        end
      end)

    case result do
      {:ok, _} = success -> success
      {:error, errors} -> {:error, Enum.reverse(errors)}
    end
  end

  defp download(url, path, expected_digest, authorization, deadline, limits, opts) do
    download_redirect(%{
      url: url,
      path: path,
      expected_digest: expected_digest,
      authorization: authorization,
      deadline: deadline,
      limits: limits,
      opts: opts,
      redirects: 0,
      delivery_path: []
    })
  end

  defp download_redirect(state) do
    with {:ok, remaining} <- remaining_time(state.deadline),
         {:ok, response} <-
           request(
             state.url,
             state.path,
             state.authorization,
             remaining,
             state.limits,
             state.opts
           ) do
      path_record = [redact_url(state.url) | state.delivery_path]

      case response.status do
        200 ->
          verify_download(state.path, state.expected_digest, Enum.reverse(path_record))

        status when status in [301, 302, 303, 307, 308] ->
          follow_redirect(response, %{state | delivery_path: path_record})

        status ->
          {:error, "server returned HTTP #{status}"}
      end
    end
  end

  defp follow_redirect(response, state) do
    if state.redirects >= state.limits.redirects do
      {:error, "redirect limit #{state.limits.redirects} exceeded"}
    else
      with {:ok, location} <- redirect_location(response),
           {:ok, next_url} <- resolve_redirect(state.url, location) do
        next_authorization =
          if same_origin?(state.url, next_url), do: state.authorization, else: nil

        download_redirect(%{
          state
          | url: next_url,
            authorization: next_authorization,
            redirects: state.redirects + 1
        })
      end
    end
  end

  defp request(url, path, authorization, timeout, limits, opts) do
    case Application.ensure_all_started(:req) do
      {:ok, _} -> request_started(url, path, authorization, timeout, limits, opts)
      {:error, reason} -> {:error, "HTTP transport failed to start: #{inspect(reason)}"}
    end
  end

  defp request_started(url, path, authorization, timeout, limits, opts) do
    case File.open(path, [:write, :binary]) do
      {:ok, io} ->
        try do
          headers = request_headers(authorization)
          into = stream_into(io, limits)

          request_opts = [
            url: url,
            method: :get,
            headers: headers,
            into: into,
            redirect: false,
            retry: false,
            raw: true,
            receive_timeout: timeout,
            request_timeout: timeout,
            finch: [pool_timeout: min(timeout, 5_000)]
          ]

          request_opts =
            case Keyword.fetch(opts, :plug) do
              {:ok, plug} -> Keyword.put(request_opts, :plug, plug)
              :error -> request_opts
            end

          case Req.request(request_opts) do
            {:ok, response} ->
              stream_result(response)

            {:error, exception} ->
              message =
                exception
                |> Exception.message()
                |> safe_message()

              {:error, "request failed: #{message}"}
          end
        after
          File.close(io)
        end

      {:error, reason} ->
        {:error, "download stage: #{:file.format_error(reason)}"}
    end
  end

  defp stream_into(io, limits) do
    fn {:data, data}, {request, response} ->
      state = Map.get(response.private, :wotex_retrieval, %{bytes: 0, error: nil})
      maximum = if response.status == 200, do: limits.response_bytes, else: limits.error_body_bytes
      next_size = state.bytes + byte_size(data)

      cond do
        next_size > maximum ->
          state = %{state | bytes: next_size, error: "response exceeds #{maximum} bytes"}
          {:halt, {request, put_stream_state(response, state)}}

        response.status == 200 ->
          case :file.write(io, data) do
            :ok ->
              state = %{state | bytes: next_size}
              {:cont, {request, put_stream_state(response, state)}}

            {:error, reason} ->
              state = %{state | error: "download stage: #{:file.format_error(reason)}"}
              {:halt, {request, put_stream_state(response, state)}}
          end

        true ->
          state = %{state | bytes: next_size}
          {:cont, {request, put_stream_state(response, state)}}
      end
    end
  end

  defp put_stream_state(response, state) do
    put_in(response.private[:wotex_retrieval], state)
  end

  defp stream_result(response) do
    case response.private[:wotex_retrieval] do
      %{error: error} when is_binary(error) -> {:error, error}
      _ -> {:ok, response}
    end
  end

  defp verify_download(path, expected_digest, delivery_path) do
    with {:ok, %{type: :regular, size: size}} <- File.lstat(path),
         {:ok, actual} <- file_digest(path),
         true <- actual == expected_digest or {:error, "transport digest mismatch"} do
      {:ok, delivery_path, size}
    else
      {:ok, %{type: type}} ->
        {:error, "download stage is #{type}, expected regular file"}

      {:error, reason} when is_atom(reason) ->
        {:error, "download stage: #{:file.format_error(reason)}"}

      {:error, _} = error ->
        error
    end
  end

  defp file_digest(path) do
    with {:ok, io} <- File.open(path, [:read, :binary]) do
      try do
        digest_chunks(io, :crypto.hash_init(:sha256))
      after
        File.close(io)
      end
    end
  end

  defp digest_chunks(io, context) do
    case IO.binread(io, 65_536) do
      :eof ->
        digest = :crypto.hash_final(context) |> Base.encode16(case: :lower)
        {:ok, digest}

      data when is_binary(data) ->
        digest_chunks(io, :crypto.hash_update(context, data))

      {:error, reason} ->
        {:error, "download stage: #{:file.format_error(reason)}"}
    end
  end

  defp redirect_location(response) do
    case Req.Response.get_header(response, "location") do
      [location] when is_binary(location) and location != "" -> {:ok, location}
      [] -> {:error, "redirect response has no Location header"}
      _ -> {:error, "redirect response has multiple Location headers"}
    end
  end

  defp resolve_redirect(current, location) do
    uri = URI.merge(URI.parse(current), URI.parse(location))

    cond do
      uri.scheme != "https" or not is_binary(uri.host) or uri.host == "" ->
        {:error, "redirect target is not HTTPS"}

      not is_nil(uri.userinfo) ->
        {:error, "redirect target contains forbidden user information"}

      not is_nil(uri.fragment) ->
        {:error, "redirect target contains a fragment"}

      true ->
        {:ok, URI.to_string(uri)}
    end
  rescue
    _ -> {:error, "redirect target is invalid"}
  end

  defp request_headers(nil), do: [{"accept-encoding", "identity"}]

  defp request_headers(authorization) do
    [{"accept-encoding", "identity"}, {"authorization", authorization}]
  end

  defp same_origin?(left, right) do
    origin(URI.parse(left)) == origin(URI.parse(right))
  end

  defp origin(uri), do: {uri.scheme, uri.host, uri.port || default_port(uri.scheme)}
  defp default_port("https"), do: 443
  defp default_port(_), do: nil

  defp remaining_time(deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    if remaining > 0, do: {:ok, remaining}, else: {:error, "retrieval deadline expired"}
  end

  defp select_sources(descriptor, nil) do
    case descriptor.raw["retrieval"]["sources"] do
      [] -> {:error, "descriptor declares no prebuilt sources"}
      sources -> {:ok, sources}
    end
  end

  defp select_sources(descriptor, name) when is_binary(name) and name != "" do
    case Enum.find(descriptor.raw["retrieval"]["sources"], &(&1["name"] == name)) do
      nil -> {:error, "descriptor does not declare retrieval source #{inspect(name)}"}
      source -> {:ok, [source]}
    end
  end

  defp select_sources(_, _), do: {:error, "retrieval source must be a non-empty name"}

  defp expand_url(template, descriptor, target, build_identity) do
    template
    |> String.replace("{package}", descriptor.package)
    |> String.replace("{profile}", descriptor.profile)
    |> String.replace("{target}", target)
    |> String.replace("{build_identity}", build_identity)
  end

  defp validate_authorization(nil, _), do: :ok

  defp validate_authorization(value, source_name)
       when is_binary(value) and value != "" and is_binary(source_name) do
    if String.contains?(value, ["\r", "\n"]),
      do: {:error, "authorization contains a prohibited line break"},
      else: :ok
  end

  defp validate_authorization(_, nil),
    do: {:error, "authorization requires selecting one exact retrieval source"}

  defp validate_authorization(_, _), do: {:error, "authorization must be a non-empty string"}

  defp validate_digest(value, label) do
    if is_binary(value) and Regex.match?(@digest, value),
      do: :ok,
      else: {:error, "#{label} must be a full lowercase SHA-256"}
  end

  defp validate_limits(%Limits{} = limits) do
    values = Map.from_struct(limits)

    cond do
      not Enum.all?(values, fn {_, value} -> is_integer(value) and value >= 0 end) ->
        {:error, "retrieval limits must be non-negative integers"}

      limits.response_bytes == 0 or limits.error_body_bytes == 0 or limits.timeout_ms == 0 ->
        {:error, "retrieval byte and time limits must be positive"}

      true ->
        :ok
    end
  end

  defp validate_cache_root(path) do
    if is_binary(path) and Path.type(path) == :absolute,
      do: :ok,
      else: {:error, "cache root must be absolute"}
  end

  defp create_stage(cache_root, build_identity) do
    downloads = Path.join(cache_root, "downloads")

    with :ok <- ensure_private_directory(cache_root, "cache root"),
         :ok <- ensure_private_directory(downloads, "download staging root") do
      token = Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
      stage = Path.join(downloads, ".#{build_identity}.stage-#{token}")

      case File.mkdir(stage) do
        :ok ->
          case File.chmod(stage, 0o700) do
            :ok -> {:ok, stage}
            {:error, reason} -> {:error, "download stage: #{:file.format_error(reason)}"}
          end

        {:error, reason} ->
          {:error, "download stage: #{:file.format_error(reason)}"}
      end
    end
  end

  defp ensure_private_directory(path, label) do
    case File.lstat(path) do
      {:ok, %{type: :directory}} ->
        File.chmod(path, 0o700)

      {:ok, %{type: type}} ->
        {:error, "#{label} is #{type}, expected directory"}

      {:error, :enoent} ->
        with :ok <- ensure_parent(path, label),
             :ok <- File.mkdir(path),
             :ok <- File.chmod(path, 0o700) do
          :ok
        else
          {:error, reason} when is_atom(reason) ->
            {:error, "#{label}: #{:file.format_error(reason)}"}

          {:error, _} = error ->
            error
        end

      {:error, reason} ->
        {:error, "#{label}: #{:file.format_error(reason)}"}
    end
  end

  defp ensure_parent(path, label) do
    parent = Path.dirname(path)

    case File.lstat(parent) do
      {:ok, %{type: :directory}} -> :ok
      {:ok, %{type: type}} -> {:error, "#{label} parent is #{type}, expected directory"}
      {:error, reason} -> {:error, "#{label} parent: #{:file.format_error(reason)}"}
    end
  end

  defp remove_stage(stage) do
    case File.lstat(stage) do
      {:ok, %{type: :directory}} -> File.rm_rf(stage)
      {:ok, _} -> File.rm(stage)
      {:error, :enoent} -> :ok
      {:error, _} -> :ok
    end

    :ok
  end

  defp redact_url(url) do
    uri = URI.parse(url)
    URI.to_string(%{uri | userinfo: nil, query: nil, fragment: nil})
  end

  defp summarize_errors(errors) do
    errors
    |> Enum.take(8)
    |> Enum.map_join("; ", &safe_message/1)
  end

  defp safe_message(message) when is_binary(message) do
    if byte_size(message) <= 512,
      do: message,
      else: String.slice(message, 0, 127) <> "…"
  end
end
