defmodule Wotex.Lab.Telemetry do
  @moduledoc """
  Lab-owned telemetry under `[:wotex, :lab, component, operation, event]`.

  Measurements never pretend to originate inside the passive upstream
  libraries: every event names the Lab component that produced it. `span/4`
  emits `:start`, then `:stop` or `:exception`, with `monotonic_time` and
  `system_time` in native units and `duration` in native units on the closing
  event; `to_milliseconds/1` is the explicit exporter conversion. Counts and
  bytes are emitted as measurements through `event/4`.

  The closing `outcome` label is derived from the result shape alone: an
  error struct's `code`, `:error` for other error tuples, the leading atom of
  any other tagged tuple or bare atom, and `:ok` for everything else.

  Metadata is allowlisted and bounded before it leaves the caller: only the
  keys in `metadata_keys/0` survive, values must be atoms, booleans, integers
  or binaries of at most `max_label_bytes/0` bytes, and anything else is
  dropped rather than truncated. Thing Descriptions, tensors, credentials,
  headers, payloads and exception reasons therefore cannot become labels; an
  exception closes the span with `outcome: :exception` and the exception
  kind only, then propagates unchanged. `thing_ref/1` derives a short,
  non-reversible reference from a Thing id so a label never carries the id
  itself. Handler failures are the concern of `:telemetry`, which detaches a
  raising handler; a span result is never affected by its observers.
  """

  @prefix [:wotex, :lab]
  @components ~w(runtime http sse mqtt directory continuum conformance nx policy scenario formal metrics)a
  @operations ~w(parse request subscription directory codec conformance encode inference decode verification dispatch cleanup export query investigation)a
  @metadata_keys ~w(scenario_id attempt spec_id seam_id thing_ref operation profile outcome kind)a
  @max_label_bytes 128

  @type component :: unquote(Enum.reduce(@components, &{:|, [], [&1, &2]}))
  @type operation :: unquote(Enum.reduce(@operations, &{:|, [], [&1, &2]}))

  @doc "Lab components allowed as the third event segment."
  @spec components() :: [component()]
  def components, do: @components

  @doc "Operations allowed as the fourth event segment."
  @spec operations() :: [operation()]
  def operations, do: @operations

  @doc "Metadata keys that may reach a handler."
  @spec metadata_keys() :: [atom()]
  def metadata_keys, do: @metadata_keys

  @doc "Largest binary label accepted, in bytes."
  @spec max_label_bytes() :: pos_integer()
  def max_label_bytes, do: @max_label_bytes

  @doc "Runs `fun` inside a start/stop or start/exception span; the result is returned unchanged."
  @spec span(component(), operation(), map(), (-> result)) :: result when result: term()
  def span(component, operation, metadata, fun)
      when component in @components and operation in @operations and is_map(metadata) and
             is_function(fun, 0) do
    metadata = metadata(metadata)
    start = System.monotonic_time()

    :telemetry.execute(
      @prefix ++ [component, operation, :start],
      %{
        monotonic_time: start,
        system_time: System.system_time()
      },
      metadata
    )

    try do
      result = fun.()
      stop(component, operation, start, Map.put(metadata, :outcome, outcome(result)))
      result
    catch
      kind, reason ->
        exception(component, operation, start, Map.put(metadata, :kind, kind))
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @doc "Emits a count or size measurement under a Lab event name."
  @spec event(component(), operation(), map(), map()) :: :ok
  def event(component, operation, measurements, metadata)
      when component in @components and operation in @operations and is_map(measurements) and
             is_map(metadata) do
    :telemetry.execute(
      @prefix ++ [component, operation, :measurement],
      measurements(measurements),
      metadata(metadata)
    )
  end

  @doc "Converts a native-unit duration or timestamp to milliseconds; the exporter conversion."
  @spec to_milliseconds(integer()) :: integer()
  def to_milliseconds(native) when is_integer(native),
    do: System.convert_time_unit(native, :native, :millisecond)

  @doc "Keeps allowlisted keys with atom, boolean, integer or short binary values."
  @spec metadata(map()) :: map()
  def metadata(map) when is_map(map) do
    map
    |> Map.take(@metadata_keys)
    |> Enum.filter(fn {_key, value} -> label?(value) end)
    |> Map.new()
  end

  @doc "Derives a short non-reversible reference for a Thing id."
  @spec thing_ref(String.t()) :: String.t()
  def thing_ref(thing_id) when is_binary(thing_id) do
    "thing:" <>
      (:crypto.hash(:sha256, thing_id) |> Base.encode16(case: :lower) |> binary_part(0, 16))
  end

  defp stop(component, operation, start, metadata) do
    now = System.monotonic_time()

    :telemetry.execute(
      @prefix ++ [component, operation, :stop],
      %{monotonic_time: now, duration: now - start},
      metadata
    )
  end

  defp exception(component, operation, start, metadata) do
    now = System.monotonic_time()

    :telemetry.execute(
      @prefix ++ [component, operation, :exception],
      %{monotonic_time: now, duration: now - start},
      Map.put(metadata, :outcome, :exception)
    )
  end

  defp outcome({:error, %{code: code}}) when is_atom(code), do: code
  defp outcome({:error, _reason}), do: :error
  defp outcome(:ignore), do: :ignored
  defp outcome(tag) when is_atom(tag) and not is_nil(tag), do: tag
  defp outcome(tuple) when is_tuple(tuple) and is_atom(elem(tuple, 0)), do: elem(tuple, 0)
  defp outcome(_other), do: :ok

  defp measurements(map) do
    map
    |> Enum.filter(fn {key, value} -> is_atom(key) and is_number(value) end)
    |> Map.new()
  end

  defp label?(value) when is_atom(value) or is_integer(value), do: true
  defp label?(value) when is_binary(value), do: byte_size(value) <= @max_label_bytes
  defp label?(_value), do: false
end
