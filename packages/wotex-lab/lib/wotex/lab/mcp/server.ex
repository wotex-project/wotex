defmodule Wotex.Lab.MCP.Server do
  @moduledoc """
  The transport-independent Model Context Protocol server core.

  `new/1` builds a session state for one explicit host: an optional Lab
  instance whose simulated Things may be listed and read, a `:writes` switch
  that is off by default, the write authorization token a host supplies when
  it opts in, the runtime credential port used to reach simulated Things
  (`:credentials`, `{NoSec, %{}}` by default), and
  quotas (`:max_calls`, `:max_output_bytes`). `handle/2` takes
  one decoded JSON-RPC message and returns `{reply | nil, state}`; it never
  reads the network, never starts a process and never grants anything a
  transport did not present explicitly. Pinned protocol version: 2025-11-25.
  Resources come from `Wotex.Lab.MCP.Resources` and tools from
  `Wotex.Lab.MCP.Tools`; every tool call is bounded by the session quota and
  the tool's own limits. Unknown methods, malformed params and exhausted quotas
  are JSON-RPC errors, not silent successes.
  """

  alias Wotex.Lab.Adapters.Runtime.NoSec
  alias Wotex.Lab.Error
  alias Wotex.Lab.MCP.{Jobs, Resources, Tools}

  @protocol_version "2025-11-25"
  @server_info %{"name" => "wotex_lab", "version" => "0.1.0"}
  @default_max_calls 1_000
  @default_max_output_bytes 8_388_608

  @type t :: %{
          instance: pid() | nil,
          credentials: {module(), term()},
          writes: boolean(),
          write_token: String.t() | nil,
          initialized: boolean(),
          calls: non_neg_integer(),
          output_bytes: non_neg_integer(),
          max_calls: pos_integer(),
          max_output_bytes: pos_integer(),
          idempotency: MapSet.t(String.t()),
          formal: keyword() | nil,
          metrics: %{history: pid(), scope: map()} | nil,
          jobs: pid() | nil,
          session_key: String.t() | nil
        }

  @doc "The pinned protocol version this server speaks."
  @spec protocol_version() :: String.t()
  def protocol_version, do: @protocol_version

  @doc """
  Builds a session. Options: `:instance` (a live `Wotex.Lab` pid), `:writes`
  (false), `:write_token` (required when writes are on), `:max_calls`,
  `:max_output_bytes`, `:formal` (keyword options for the formal profile, or nil)
  and `:metrics` (`%{history: pid, scope: map}` bound from the host's authenticated
  context, or nil). The metrics scope never comes from a tool argument. `:jobs`
  is a host-started `Wotex.Lab.MCP.Jobs` pid, or nil; a bound session gets a
  random job key.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Wotex.Lab.Error.t()}
  def new(opts \\ []) when is_list(opts) do
    writes = Keyword.get(opts, :writes, false)
    token = Keyword.get(opts, :write_token)
    metrics = Keyword.get(opts, :metrics)
    jobs = Keyword.get(opts, :jobs)

    cond do
      not is_boolean(writes) ->
        {:error, Error.new(:invalid_options, :construction, "writes must be a boolean")}

      writes and not (is_binary(token) and byte_size(token) >= 16) ->
        {:error,
         Error.new(
           :write_token_required,
           :construction,
           "writes need an explicit token of at least 16 bytes"
         )}

      not (is_nil(jobs) or is_pid(jobs)) ->
        {:error, Error.new(:invalid_options, :construction, "jobs must be a job owner pid")}

      not metrics_binding?(metrics) ->
        {:error,
         Error.new(:invalid_options, :construction, "metrics must bind a history pid and a scope")}

      true ->
        {:ok,
         %{
           instance: Keyword.get(opts, :instance),
           credentials: Keyword.get(opts, :credentials, {NoSec, %{}}),
           writes: writes,
           write_token: token,
           initialized: false,
           calls: 0,
           output_bytes: 0,
           max_calls: Keyword.get(opts, :max_calls, @default_max_calls),
           max_output_bytes: Keyword.get(opts, :max_output_bytes, @default_max_output_bytes),
           idempotency: MapSet.new(),
           formal: Keyword.get(opts, :formal),
           metrics: metrics,
           jobs: jobs,
           session_key: if(jobs, do: Jobs.session_key())
         }}
    end
  end

  defp metrics_binding?(nil), do: true

  defp metrics_binding?(%{history: history, scope: scope} = binding),
    do: map_size(binding) == 2 and is_pid(history) and is_map(scope)

  defp metrics_binding?(_), do: false

  @doc "Handles one decoded JSON-RPC message; notifications yield a nil reply."
  @spec handle(t(), map()) :: {map() | nil, t()}
  def handle(state, %{"jsonrpc" => "2.0", "method" => method} = message) when is_binary(method) do
    id = Map.get(message, "id")
    params = Map.get(message, "params", %{})

    cond do
      not is_map(params) -> {error(id, -32_602, "params must be an object"), state}
      is_nil(id) -> {nil, notification(state, method, params)}
      true -> request(state, id, method, params)
    end
  end

  def handle(state, %{"jsonrpc" => "2.0", "id" => id}) when not is_nil(id),
    do: {error(id, -32_600, "request needs a method"), state}

  def handle(state, _),
    do: {error(nil, -32_600, "message is not a JSON-RPC 2.0 request"), state}

  defp notification(state, "notifications/initialized", _), do: %{state | initialized: true}
  defp notification(state, _, _), do: state

  defp request(state, id, "initialize", params) do
    requested = Map.get(params, "protocolVersion")
    version = if requested == @protocol_version, do: requested, else: @protocol_version

    {result(id, %{
       "protocolVersion" => version,
       "capabilities" => %{
         "resources" => %{"listChanged" => false},
         "tools" => %{"listChanged" => false}
       },
       "serverInfo" => @server_info,
       "instructions" =>
         "WoTEx Lab: read package, spec, seam, scenario, Thing and evidence metadata; parse and validate Thing Descriptions; " <>
           "read simulated Things. Writes are off unless the host opted in with a token. Nothing here authorizes a physical Action."
     }), state}
  end

  defp request(state, id, "ping", _), do: {result(id, %{}), state}

  defp request(state, id, "resources/list", _),
    do: {result(id, %{"resources" => Resources.list(state)}), state}

  defp request(state, id, "resources/read", %{"uri" => uri}) when is_binary(uri) do
    case Resources.read(state, uri) do
      {:ok, contents} -> account(state, id, %{"contents" => contents})
      {:error, code, message} -> {error(id, code, message), state}
    end
  end

  defp request(state, id, "resources/read", _),
    do: {error(id, -32_602, "uri is required"), state}

  defp request(state, id, "tools/list", _),
    do: {result(id, %{"tools" => Tools.list(state)}), state}

  defp request(state, id, "tools/call", %{"name" => name} = params) when is_binary(name) do
    arguments = Map.get(params, "arguments", %{})

    cond do
      state.calls >= state.max_calls ->
        {error(id, -32_000, "session call quota exhausted"), state}

      not is_map(arguments) ->
        {error(id, -32_602, "arguments must be an object"), state}

      true ->
        case Tools.call(state, name, arguments) do
          {:ok, content, state} -> account(%{state | calls: state.calls + 1}, id, content)
          {:error, code, message} -> {error(id, code, message), %{state | calls: state.calls + 1}}
        end
    end
  end

  defp request(state, id, "tools/call", _),
    do: {error(id, -32_602, "name is required"), state}

  defp request(state, id, method, _),
    do: {error(id, -32_601, "method not found: #{String.slice(method, 0, 64)}"), state}

  defp account(state, id, payload) do
    bytes = payload |> :erlang.term_to_binary() |> byte_size()

    if state.output_bytes + bytes > state.max_output_bytes,
      do: {error(id, -32_000, "session output quota exhausted"), state},
      else: {result(id, payload), %{state | output_bytes: state.output_bytes + bytes}}
  end

  defp result(id, payload), do: %{"jsonrpc" => "2.0", "id" => id, "result" => payload}

  defp error(id, code, message),
    do: %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
end
