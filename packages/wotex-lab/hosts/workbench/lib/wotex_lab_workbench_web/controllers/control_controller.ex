defmodule WotexLabWorkbenchWeb.ControlController do
  @moduledoc """
  The bounded JSON implementation of the generated control schema.

  Static catalogue operations are public and inert. Evidence and run reads are
  available only with an exact bearer token for the room that retained them.
  The `startRun`, `cancelRun` and `approveDecision` mutations also require the
  host's `control_mutations` opt-in. Before any session is read, a mutation
  must carry an admitted `Origin` (or none), a JSON media type, no query string
  and a counted body of at most 4,096 bytes. The action then checks the bearer,
  delegates key and body admission to `WotexLabWorkbench.Control`, verifies the
  session, takes a `WotexLabWorkbench.Control.Limits` slot and lets the session
  room execute the command at most once per `Idempotency-Key`. A replayed
  answer carries `Idempotent-Replayed: true`. `queryMetrics` is read-only and
  needs no opt-in: it takes the same JSON media type, query-string and body
  bounds, checks the bearer and asks `WotexLabWorkbench.Control` to answer the
  closed query descriptor from that session room's attributed history. Responses are never cached and
  errors retain the family's stable code/phase/path/message shape.
  """

  use WotexLabWorkbenchWeb, :controller

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.{Control, Sessions}
  alias WotexLabWorkbench.Control.Limits
  alias WotexLabWorkbenchWeb.Plugs.BodyReader

  @max_mutation_body_bytes 4_096
  @mutations [:start_run, :cancel_run, :approve_decision]
  @statuses %{
    invalid_request: 400,
    invalid_query: 400,
    invalid_filter: 400,
    invalid_aggregation: 400,
    invalid_range: 400,
    invalid_step: 400,
    invalid_quantile: 400,
    unknown_history: 404,
    clock_rollback: 409,
    unsupported_query: 422,
    query_too_large: 422,
    output_too_large: 422,
    too_many_queries: 429,
    history_unavailable: 503,
    invalid_body: 400,
    invalid_idempotency_key: 400,
    missing_bearer: 401,
    mutations_disabled: 403,
    origin_refused: 403,
    unknown_run: 404,
    idempotency_capacity: 409,
    body_too_large: 413,
    unsupported_media_type: 415,
    unknown_experiment: 422,
    unknown_parameter: 422,
    invalid_parameter: 422,
    idempotency_key_reused: 422,
    concurrency_limited: 429,
    rate_limited: 429,
    room_unavailable: 503,
    deadline_exceeded: 504
  }

  plug :mutation_guard when action in @mutations
  plug :query_guard when action == :query_metrics

  @doc "Lists the admitted scenario descriptors."
  @spec scenarios(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def scenarios(conn, _), do: reply(conn, 200, %{"scenarios" => Control.scenarios()})

  @doc "Reads one admitted scenario descriptor."
  @spec scenario(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def scenario(conn, %{"id" => id}) do
    case Control.fetch_scenario(id) do
      {:ok, descriptor} -> reply(conn, 200, descriptor)
      {:error, %Error{code: :invalid_scenario_id} = reason} -> error(conn, 400, reason)
      {:error, error} -> error(conn, 404, error)
    end
  end

  @doc "Reads one evidence record from the caller's existing session room."
  @spec evidence(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def evidence(conn, %{"record_id" => record_id}) do
    with {:ok, token} <- bearer(conn),
         {:ok, %{room: room}} when is_pid(room) <- Sessions.verify(token),
         {:ok, record} <- Control.fetch_evidence(room, record_id) do
      reply(conn, 200, record)
    else
      {:ok, _} ->
        error(conn, 404, api_error(:unknown_evidence, "evidence record is not retained"))

      {:error, %Error{code: :unknown_evidence} = reason} ->
        error(conn, 404, reason)

      {:error, %Error{code: :invalid_record_id} = reason} ->
        error(conn, 400, reason)

      {:error, %Error{} = reason} ->
        error(conn, 403, reason)

      {:error, :missing_bearer} ->
        error(conn, 401, missing_bearer())
    end
  end

  @doc "Reads the versioned metric catalogue."
  @spec metrics_catalogue(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def metrics_catalogue(conn, _), do: reply(conn, 200, Control.metrics_catalogue())

  @doc "Answers one closed metric query descriptor from the caller's session room history."
  @spec query_metrics(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def query_metrics(conn, _) do
    with {:ok, token} <- bearer(conn),
         {:ok, %{room: room}} when is_pid(room) <- Sessions.verify(token),
         {:ok, answer} <- Control.query_metrics(room, conn.body_params) do
      reply(conn, 200, answer)
    else
      {:ok, _} -> error(conn, 404, api_error(:unknown_history, "the session has no room history"))
      {:error, :missing_bearer} -> error(conn, 401, missing_bearer())
      {:error, %Error{} = reason} -> failure(conn, reason)
    end
  end

  @doc "Reads one run projection from the caller's existing session room."
  @spec run(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def run(conn, %{"run_id" => run_id}) do
    with {:ok, token} <- bearer(conn),
         {:ok, %{room: room}} when is_pid(room) <- Sessions.verify(token),
         {:ok, run} <- Control.fetch_run(room, run_id) do
      reply(conn, 200, run)
    else
      {:ok, _} -> error(conn, 404, api_error(:unknown_run, "run is not retained"))
      {:error, :missing_bearer} -> error(conn, 401, missing_bearer())
      {:error, %Error{} = reason} -> failure(conn, reason)
    end
  end

  @doc "Starts an admitted experiment run in the caller's session room."
  @spec start_run(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def start_run(conn, _), do: mutate(conn, :start_run, nil, 201)

  @doc "Cancels the pending decision of a run in the caller's session room."
  @spec cancel_run(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def cancel_run(conn, %{"run_id" => run_id}), do: mutate(conn, :cancel_run, run_id, 200)

  @doc "Approves the exactly named granted decision of a run in the caller's session room."
  @spec approve_decision(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def approve_decision(conn, %{"run_id" => run_id}),
    do: mutate(conn, :approve_decision, run_id, 200)

  defp mutate(conn, operation, run_id, success) do
    with {:ok, token} <- bearer(conn),
         {:ok, admitted} <-
           Control.admit_mutation(operation, run_id, idempotency_key(conn), conn.body_params),
         {:ok, session} <- Sessions.verify(token),
         {:ok, slot} <- Limits.acquire(session.id) do
      try do
        execute(conn, token, admitted, success)
      after
        Limits.release(slot)
      end
    else
      {:error, :missing_bearer} -> error(conn, 401, missing_bearer())
      {:error, %Error{} = reason} -> failure(conn, reason)
    end
  end

  defp execute(conn, token, admitted, success) do
    with {:ok, %{room: room}} <- Sessions.admit(token, admitted.command),
         {:ok, mode, run} <- Control.mutate(room, admitted) do
      conn
      |> put_replayed(mode)
      |> reply(success, run)
    else
      {:error, mode, %Error{} = reason} ->
        conn
        |> put_replayed(mode)
        |> failure(reason)

      {:error, %Error{code: :no_room}} ->
        error(conn, 404, api_error(:unknown_run, "run is not retained"))

      {:error, %Error{} = reason} ->
        failure(conn, reason)
    end
  end

  defp mutation_guard(conn, _) do
    with :ok <- enabled(),
         :ok <- origin(conn),
         :ok <- media_type(conn),
         :ok <- no_query(conn),
         :ok <- body_size(conn) do
      conn
    else
      {:error, %Error{} = reason} -> halt(failure(conn, reason))
    end
  end

  defp query_guard(conn, _) do
    with :ok <- media_type(conn),
         :ok <- no_query(conn),
         :ok <- body_size(conn) do
      conn
    else
      {:error, %Error{} = reason} -> halt(failure(conn, reason))
    end
  end

  defp enabled do
    if is_list(Application.get_env(:wotex_lab_workbench, :control_mutations, false)) and
         is_pid(GenServer.whereis(Limits)),
       do: :ok,
       else: {:error, api_error(:mutations_disabled, "control mutations are not enabled")}
  end

  defp origin(conn) do
    case get_req_header(conn, "origin") do
      [] ->
        :ok

      [origin] ->
        if origin == WotexLabWorkbenchWeb.Endpoint.url() or origin in Limits.origins(),
          do: :ok,
          else: origin_refused()

      _ ->
        origin_refused()
    end
  end

  defp media_type(conn) do
    with [content_type] <- get_req_header(conn, "content-type"),
         {:ok, "application", "json", _} <- Plug.Conn.Utils.media_type(content_type) do
      :ok
    else
      _ ->
        {:error, api_error(:unsupported_media_type, "this operation accepts application/json only")}
    end
  end

  defp no_query(%{query_string: ""}), do: :ok

  defp no_query(_),
    do: {:error, api_error(:invalid_request, "this operation accepts no query parameters")}

  defp body_size(conn) do
    if BodyReader.bytes(conn) <= @max_mutation_body_bytes,
      do: :ok,
      else: {:error, api_error(:body_too_large, "body exceeds #{@max_mutation_body_bytes} bytes")}
  end

  defp idempotency_key(conn) do
    case get_req_header(conn, "idempotency-key") do
      [key] -> key
      _ -> nil
    end
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when byte_size(token) in 16..128 -> {:ok, token}
      _ -> {:error, :missing_bearer}
    end
  end

  defp put_replayed(conn, :replayed), do: put_resp_header(conn, "idempotent-replayed", "true")
  defp put_replayed(conn, _), do: conn

  defp failure(conn, %Error{code: :rate_limited, details: %{retry_after_ms: ms}} = reason) do
    conn
    |> put_resp_header("retry-after", Integer.to_string(div(ms + 999, 1_000)))
    |> error(429, reason)
  end

  defp failure(conn, %Error{} = reason), do: error(conn, status(reason), reason)

  defp status(%Error{code: code, phase: phase}) do
    case Map.fetch(@statuses, code) do
      {:ok, status} -> status
      :error when phase == :session -> 403
      :error -> 409
    end
  end

  defp reply(conn, status, body) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> json(body)
  end

  defp error(conn, status, %Error{} = reason) do
    reply(conn, status, %{
      "code" => Atom.to_string(reason.code),
      "phase" => Atom.to_string(reason.phase),
      "path" => reason.path,
      "message" => reason.message
    })
  end

  defp origin_refused, do: {:error, api_error(:origin_refused, "origin is not admitted")}
  defp missing_bearer, do: api_error(:missing_bearer, "bearer token is required")
  defp api_error(code, message), do: Error.new(code, :control_api, message)
end
