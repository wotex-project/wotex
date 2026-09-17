defmodule Wotex.Lab.MCP.Tools do
  @moduledoc """
  Bounded MCP tools over public package APIs.

  Read-oriented tools: `parse_td` and `parse_tm` run the core parsers on a
  document of at most 1 MiB and return the projection or the structured
  errors; `explain_error` explains a code, phase and path in Lab terms;
  `list_things` and `read_property` reach the simulated Things of the
  session's explicit instance through the runtime and the loopback transport;
  `conformance_observe` derives one conformance observation with the Lab
  target; `explain_seam` answers an ownership question from the seam table;
  `verify_control_model` runs the optional formal profile when the host
  configured one and otherwise reports `unsupported`. `query_metrics` exists only
  when the host bound a metrics history and scope: each call opens one disposable
  `Wotex.Lab.Metrics.Gateway` owned by the session process, admits the closed
  request fields with the tool's reduced limits, waits at most two seconds and
  revokes the gateway. `invoke_action` exists
  only when the host opted into writes: it needs the host's write token, an
  idempotency key that is never accepted twice in a session, and a deadline,
  and it dispatches through the runtime against a simulated Thing of this
  instance only. No tool fetches a URL, reads an arbitrary path, downloads a
  model, accepts raw Maude text or returns a credential.
  """

  alias Wotex.Lab.Conformance.Target
  alias Wotex.Lab.Formal.{Abstraction, Model, Profile, Result, Serializer}
  alias Wotex.Lab.MCP.{Resources, Seams}
  alias Wotex.Lab.Metrics.{Gateway, Query}
  alias Wotex.Lab.Reference.Thing
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context}
  alias Wotex.{ThingDescription, ThingModel}

  @tool_names ~w(parse_td parse_tm explain_error list_things read_property conformance_observe explain_seam verify_control_model query_metrics invoke_action)
  @metric_fields ~w(metric aggregation filters quantile start_at end_at step_ms)
  @metric_limits %{
    range_ms: 6 * 60 * 60 * 1_000,
    min_step_ms: 5_000,
    points: 2_000,
    output_bytes: 262_144,
    deadline_ms: 2_000,
    concurrent: 1
  }
  @max_document_bytes 1_048_576
  @max_deadline_ms 30_000
  @phases %{
    "parse" => "the bytes are not a JSON document within the admission limits",
    "value" => "the JSON value has the wrong shape for this member",
    "schema" => "the document violates the pinned TD 1.1 JSON Schema at this pointer",
    "semantic" => "the document is well formed but breaks a WoT semantic rule",
    "encode" => "the value cannot be encoded canonically",
    "construction" => "the Lab value was built from invalid options",
    "admission" => "the request was refused before any work started",
    "policy" => "the decision policy refused; nothing was dispatched",
    "channel" => "the Continuum channel refused the delivery",
    "engine" => "the formal engine did not answer within the bounds"
  }

  @doc "Tool definitions visible to the session."
  @spec list(map()) :: [map()]
  def list(state) do
    read = [
      tool(
        "parse_td",
        "Parse and validate a Thing Description; returns the projection or structured errors.",
        %{"document" => %{"type" => "string"}},
        ["document"]
      ),
      tool(
        "parse_tm",
        "Parse and validate a Thing Model.",
        %{"document" => %{"type" => "string"}},
        ["document"]
      ),
      tool(
        "explain_error",
        "Explain a WoTEx error code, phase and path.",
        %{
          "code" => %{"type" => "string"},
          "phase" => %{"type" => "string"},
          "path" => %{"type" => "string"}
        },
        ["code", "phase"]
      ),
      tool("list_things", "List the simulated Things of this session's instance.", %{}, []),
      tool(
        "read_property",
        "Read a Property of a simulated Thing through the runtime.",
        %{
          "thing_id" => %{"type" => "string"},
          "property" => %{"type" => "string"},
          "deadline_ms" => %{"type" => "integer"}
        },
        ["thing_id", "property"]
      ),
      tool(
        "conformance_observe",
        "Derive one conformance observation from a document and a projection.",
        %{
          "operation" => %{"type" => "string"},
          "document" => %{},
          "projection" => %{"type" => "array"}
        },
        ["operation", "document"]
      ),
      tool(
        "explain_seam",
        "Answer an ownership question by seam id.",
        %{"seam" => %{"type" => "string"}},
        ["seam"]
      ),
      tool(
        "verify_control_model",
        "Run the optional formal profile on the thermal control model.",
        %{"variant" => %{"type" => "string"}, "property" => %{"type" => "string"}},
        ["variant", "property"]
      )
    ]

    write = [
      tool(
        "invoke_action",
        "Invoke an Action on a simulated Thing of this instance (host opted into writes).",
        %{
          "thing_id" => %{"type" => "string"},
          "action" => %{"type" => "string"},
          "input" => %{},
          "authorization" => %{"type" => "string"},
          "idempotency_key" => %{"type" => "string"},
          "deadline_ms" => %{"type" => "integer"}
        },
        ["thing_id", "action", "authorization", "idempotency_key"]
      )
    ]

    metrics = [
      tool(
        "query_metrics",
        "Query the host-bound metrics history with a closed catalogue descriptor.",
        %{
          "metric" => %{"type" => "string"},
          "aggregation" => %{"type" => "string"},
          "filters" => %{"type" => "object"},
          "quantile" => %{"type" => "number"},
          "start_at" => %{"type" => "string"},
          "end_at" => %{"type" => "string"},
          "step_ms" => %{"type" => "integer"}
        },
        ["metric", "aggregation", "start_at", "end_at", "step_ms"]
      )
    ]

    read = if Map.get(state, :metrics), do: read ++ metrics, else: read
    if state.writes, do: read ++ write, else: read
  end

  @doc "Executes one tool call."
  @spec call(map(), String.t(), map()) :: {:ok, map(), map()} | {:error, integer(), String.t()}
  def call(state, "parse_td", %{"document" => document}) when is_binary(document),
    do: parse(state, document, &ThingDescription.parse/1, &ThingDescription.to_map/1)

  def call(state, "parse_tm", %{"document" => document}) when is_binary(document),
    do: parse(state, document, &ThingModel.parse/1, &ThingModel.to_map/1)

  def call(state, "explain_error", %{"code" => code, "phase" => phase} = args)
      when is_binary(code) and is_binary(phase) do
    explanation = Map.get(@phases, phase, "an unknown phase; only the listed phases are explained")

    text(state, %{
      "code" => String.slice(code, 0, 64),
      "phase" => String.slice(phase, 0, 32),
      "path" => args |> Map.get("path", "/") |> to_string() |> String.slice(0, 256),
      "explanation" => explanation,
      "guidance" =>
        "Match on code, phase and path; messages may improve without notice and are not a contract."
    })
  end

  def call(state, "list_things", _) do
    things =
      case state.instance do
        pid when is_pid(pid) ->
          Enum.map(Resources.reference_things(pid), fn {id, thing} ->
            document =
              thing |> Thing.thing_description() |> ThingDescription.to_map()

            %{
              "id" => id,
              "title" => document["title"],
              "properties" => Map.keys(document["properties"] || %{}),
              "actions" => Map.keys(document["actions"] || %{}),
              "transport" => "loopback"
            }
          end)

        _ ->
          []
      end

    text(state, %{
      "things" => things,
      "instance" => if(is_pid(state.instance), do: "explicit", else: "none")
    })
  end

  def call(state, "read_property", %{"thing_id" => thing_id, "property" => property} = args)
      when is_binary(thing_id) and is_binary(property) do
    with {:ok, deadline} <- deadline(args),
         {:ok, thing} <- thing(state, thing_id),
         {:ok, consumed} <- consumed(state, thing),
         {:ok, result} <-
           ConsumedThing.read_property(
             consumed,
             property,
             context("mcp-read", deadline)
           ) do
      text(state, %{
        "thing_id" => thing_id,
        "property" => property,
        "value" => result.payload,
        "status" => Atom.to_string(result.status)
      })
    else
      {:error, code, message} ->
        {:error, code, message}

      {:error, %{code: code} = error} ->
        text(
          state,
          %{
            "error" => %{
              "code" => Atom.to_string(code),
              "phase" => phase(error),
              "path" => Map.get(error, :path)
            }
          },
          true
        )
    end
  end

  def call(state, "conformance_observe", %{"operation" => operation, "document" => document} = args)
      when is_binary(operation) do
    projection = Map.get(args, "projection", [])

    if is_list(projection) and length(projection) <= 64 and Enum.all?(projection, &is_binary/1) do
      request = %{
        "vector" => %{
          "id" => "mcp",
          "input" => %{"document" => document, "projection" => projection}
        },
        "claim" => %{"operation" => operation}
      }

      text(state, Target.respond(request))
    else
      {:error, -32_602, "projection must be a list of at most 64 pointers"}
    end
  end

  def call(state, "explain_seam", %{"seam" => seam}) when is_binary(seam) do
    case Seams.fetch(seam) do
      {:ok, entry} ->
        text(state, entry)

      :error ->
        text(
          state,
          %{"error" => "unknown seam", "known" => Enum.map(Seams.all(), & &1["id"])},
          true
        )
    end
  end

  def call(state, "verify_control_model", %{"variant" => variant, "property" => property})
      when is_binary(variant) and is_binary(property) do
    case state.formal do
      nil ->
        text(state, %{
          "status" => "unsupported",
          "reason" => "no formal profile configured by the host"
        })

      opts ->
        verify(state, opts, variant, property)
    end
  end

  def call(
        %{writes: true} = state,
        "invoke_action",
        %{
          "thing_id" => thing_id,
          "action" => action,
          "authorization" => token,
          "idempotency_key" => key
        } =
          args
      )
      when is_binary(thing_id) and is_binary(action) and is_binary(token) and is_binary(key) do
    with :ok <- authorize(state, token, key) do
      state = %{state | idempotency: MapSet.put(state.idempotency, key)}
      invoke(state, thing_id, action, Map.get(args, "input"), args)
    end
  end

  def call(%{metrics: %{history: history, scope: scope}} = state, "query_metrics", args)
      when is_map(args) do
    if Enum.all?(Map.keys(args), &(&1 in @metric_fields)) do
      request = Map.put(args, "schema_version", Query.schema_version())
      query_metrics(state, history, scope, request)
    else
      {:error, -32_602, "invalid arguments for query_metrics"}
    end
  end

  def call(%{metrics: nil}, "query_metrics", _),
    do: {:error, -32_601, "metrics are not bound to this session"}

  def call(%{writes: false}, "invoke_action", _),
    do: {:error, -32_601, "writes are not enabled for this session"}

  def call(_, name, _) when name in @tool_names,
    do: {:error, -32_602, "invalid arguments for #{name}"}

  def call(_, name, _), do: {:error, -32_601, "unknown tool: #{String.slice(name, 0, 64)}"}

  defp authorize(state, token, key) do
    cond do
      not Plug.Crypto.secure_compare(token, state.write_token || "") ->
        {:error, -32_001, "authorization refused"}

      byte_size(key) == 0 or byte_size(key) > 128 ->
        {:error, -32_602, "idempotency_key must be 1..128 bytes"}

      MapSet.member?(state.idempotency, key) ->
        {:error, -32_001, "idempotency_key was already used in this session"}

      true ->
        :ok
    end
  end

  defp parse(_, document, _, _) when byte_size(document) > @max_document_bytes,
    do: {:error, -32_602, "document exceeds #{@max_document_bytes} bytes"}

  defp parse(state, document, parser, projection) do
    case parser.(document) do
      {:ok, value} ->
        text(state, %{"accepted" => true, "document" => projection.(value)})

      {:error, errors} when is_list(errors) ->
        text(state, %{"accepted" => false, "errors" => Enum.map(errors, &error_map/1)}, true)

      {:error, error} ->
        text(state, %{"accepted" => false, "errors" => [error_map(error)]}, true)
    end
  end

  defp error_map(%{code: code, phase: phase} = error),
    do: %{
      "code" => Atom.to_string(code),
      "phase" => Atom.to_string(phase),
      "path" => Map.get(error, :path),
      "message" => Map.get(error, :message)
    }

  defp phase(%{phase: phase}) when is_atom(phase), do: Atom.to_string(phase)

  defp deadline(args) do
    case Map.get(args, "deadline_ms", 5_000) do
      ms when is_integer(ms) and ms > 0 and ms <= @max_deadline_ms -> {:ok, ms}
      _ -> {:error, -32_602, "deadline_ms must be 1..#{@max_deadline_ms}"}
    end
  end

  defp thing(state, thing_id) do
    case Resources.fetch_thing(state, thing_id) do
      {:ok, pid} -> {:ok, pid}
      :error -> {:error, -32_002, "no such simulated Thing in this instance"}
    end
  end

  if Code.ensure_loaded?(Wotex.Runtime.ConsumedThing) do
    defp consumed(state, thing) do
      td = Thing.thing_description(thing)

      with {:ok, profile} <-
             BindingProfile.new(
               id: :loopback,
               schemes: ["loopback"],
               operations: Wotex.Runtime.operations()
             ) do
        ConsumedThing.new(td,
          profiles: [profile],
          transports: %{loopback: {Wotex.Lab.Adapters.Runtime.Loopback, %{host: thing}}},
          credentials: state.credentials
        )
      end
    end

    defp context(label, deadline),
      do:
        Context.new!(
          request_id: label,
          deadline: System.monotonic_time(:millisecond) + deadline
        )
  else
    defp consumed(_, _),
      do: {:error, -32_601, "the runtime profile is not part of this host"}

    defp context(_, _), do: nil
  end

  defp invoke(state, thing_id, action, input, args) do
    with {:ok, deadline} <- deadline(args),
         {:ok, thing} <- thing(state, thing_id),
         {:ok, consumed} <- consumed(state, thing),
         {:ok, result} <-
           ConsumedThing.invoke_action(
             consumed,
             action,
             input,
             context("mcp-invoke", deadline)
           ) do
      text(state, %{
        "thing_id" => thing_id,
        "action" => action,
        "status" => Atom.to_string(result.status),
        "output" => result.payload
      })
    else
      {:error, code, message} when is_integer(code) ->
        {:error, code, message}

      {:error, %{code: code} = error} ->
        text(state, %{"error" => %{"code" => Atom.to_string(code), "phase" => phase(error)}}, true)
    end
  end

  if Code.ensure_loaded?(ExMaude.Pool) do
    defp verify(state, opts, variant, property) do
      variants = Map.new(Model.variants(), &{Atom.to_string(&1), &1})

      properties =
        Map.new(Serializer.properties(), fn {id, _} ->
          {Atom.to_string(id), id}
        end)

      with {:ok, variant} <- closed(variants, variant, "variant"),
           {:ok, property} <- closed(properties, property, "property"),
           {:ok, profile} <- Profile.new(opts),
           {:ok, result} <-
             Profile.verify(
               profile,
               variant,
               property,
               Abstraction.init()
             ) do
        text(state, Result.to_map(result))
      else
        {:error, code, message} when is_integer(code) ->
          {:error, code, message}

        {:error, %{code: code}} ->
          text(state, %{"status" => "unsupported", "reason" => Atom.to_string(code)}, true)
      end
    end
  else
    defp verify(state, _, _, _),
      do:
        text(state, %{
          "status" => "unsupported",
          "reason" => "the formal profile is not part of this host"
        })
  end

  defp closed(table, value, field) do
    case Map.fetch(table, value) do
      {:ok, atom} -> {:ok, atom}
      :error -> {:error, -32_602, "#{field} must be one of #{Enum.join(Map.keys(table), ", ")}"}
    end
  end

  defp query_metrics(state, history, scope, request) do
    case Gateway.start_link(
           history: history,
           scope: scope,
           owner: self(),
           ttl_ms: 2_500,
           max_calls: 1,
           query_limits: @metric_limits
         ) do
      {:ok, gateway} ->
        Process.unlink(gateway)
        monitor = Process.monitor(gateway)

        try do
          case Gateway.query(gateway, request) do
            {:ok, reference} -> await_metrics(state, gateway, monitor, reference)
            {:error, error} -> metrics_failure(state, error.code)
          end
        after
          _ = Gateway.revoke(gateway)
          Process.demonitor(monitor, [:flush])
          flush_metrics(gateway)
        end

      {:error, error} ->
        metrics_failure(state, error.code)
    end
  end

  defp await_metrics(state, gateway, monitor, reference) do
    receive do
      {:metric_query, ^gateway, ^reference, {:ok, answer}} -> text(state, json_value(answer))
      {:metric_query, ^gateway, ^reference, {:error, error}} -> metrics_failure(state, error.code)
      {:DOWN, ^monitor, :process, ^gateway, _} -> metrics_failure(state, :scope_unavailable)
    after
      @metric_limits.deadline_ms + 250 ->
        _ = Gateway.cancel(gateway, reference)
        metrics_failure(state, :deadline_exceeded)
    end
  end

  defp flush_metrics(gateway) do
    receive do
      {:metric_query, ^gateway, _, _} -> flush_metrics(gateway)
    after
      0 -> :ok
    end
  end

  defp metrics_failure(state, code),
    do: text(state, %{"available" => false, "error" => Atom.to_string(code)}, true)

  defp json_value(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp json_value(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {json_key(key), json_value(item)} end)

  defp json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)
  defp json_value(value) when is_boolean(value) or is_nil(value), do: value
  defp json_value(value) when is_atom(value), do: Atom.to_string(value)
  defp json_value(value) when is_tuple(value), do: value |> Tuple.to_list() |> json_value()
  defp json_value(value), do: value

  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key) when is_binary(key), do: key
  defp json_key(key), do: inspect(key)

  defp text(state, payload, error? \\ false) do
    case Wotex.JSON.encode(payload) do
      {:ok, json} ->
        {:ok,
         %{
           "content" => [%{"type" => "text", "text" => json}],
           "structuredContent" => payload,
           "isError" => error?
         }, state}

      {:error, _} ->
        {:error, -32_000, "tool result is not encodable"}
    end
  end

  defp tool(name, description, properties, required),
    do: %{
      "name" => name,
      "description" => description,
      "inputSchema" => %{"type" => "object", "properties" => properties, "required" => required}
    }
end
