defmodule Wotex.BLE.Native.Command do
  @moduledoc """
  Runs one explicit native build step through the packaged command guardian.

  `run/2` accepts an absolute guardian executable and a complete step map. The
  executable, arguments, working directory and environment remain separate
  values; inherited environment variables are cleared before spawn. The
  guardian owns the child process group, closes stdin to `/dev/null`, bounds
  combined output and time even while the BEAM caller is suspended, and cleans
  up ordinary descendants on deadline, overflow or owner loss.

  The caller waits the step deadline plus its cleanup allowance and a further
  500 ms for guardian status delivery. A nil exit status means no final status
  was observed. Returned output is bounded build evidence, not a protocol value.
  Descendants that deliberately leave the owned process group are outside this
  boundary.
  """

  @fields ~w(id executable args cwd env timeout_ms output_bytes cleanup_ms)a
  @codes %{
    124 => :command_deadline,
    125 => :command_output_limit,
    126 => :command_setup_failed,
    127 => :command_owner_lost,
    128 => :command_terminated,
    129 => :command_cleanup_failed
  }

  @typedoc "A finite build step with an explicit environment allowlist."
  @type step :: %{
          id: atom(),
          executable: String.t(),
          args: [String.t()],
          cwd: String.t(),
          env: [{String.t(), String.t() | nil}],
          timeout_ms: pos_integer(),
          output_bytes: pos_integer(),
          cleanup_ms: pos_integer()
        }

  @typedoc "Bounded output and the observed status; nil means no final status arrived."
  @type result :: %{output: binary(), exit_status: non_neg_integer() | nil}

  @doc "Executes a validated step and retains its bounded output on success or failure."
  @spec run(term(), term()) :: {:ok, result()} | {:error, atom(), result()}
  def run(guardian, step) when is_binary(guardian) and is_map(step) do
    if absolute?(guardian) and valid_step?(step),
      do: execute(guardian, step),
      else: failure(:invalid_command, <<>>, nil)
  end

  def run(_, _), do: failure(:invalid_command, <<>>, nil)

  defp valid_step?(step) do
    MapSet.new(Map.keys(step)) == MapSet.new(@fields) and is_atom(step.id) and
      absolute?(step.executable) and absolute?(step.cwd) and arguments?(step.args) and
      environment?(step.env) and bounded?(step.timeout_ms, 600_000) and
      bounded?(step.output_bytes, 16_777_216) and bounded?(step.cleanup_ms, 5000)
  end

  defp absolute?(path) do
    is_binary(path) and byte_size(path) in 1..4096 and String.valid?(path) and
      Path.type(path) == :absolute and not String.contains?(path, <<0>>)
  end

  defp arguments?(args) do
    is_list(args) and length(args) <= 256 and Enum.all?(args, &argument?/1) and
      Enum.reduce(args, 0, &(byte_size(&1) + &2)) <= 65_536
  end

  defp argument?(arg) do
    is_binary(arg) and byte_size(arg) <= 8192 and String.valid?(arg) and
      not String.contains?(arg, <<0>>)
  end

  defp environment?(entries) do
    is_list(entries) and length(entries) <= 64 and Enum.all?(entries, &environment_entry?/1) and
      length(Enum.uniq_by(entries, &elem(&1, 0))) == length(entries)
  end

  defp environment_entry?(entry) do
    match?({key, _} when is_binary(key), entry) and byte_size(elem(entry, 0)) <= 128 and
      String.match?(elem(entry, 0), ~r/\A[A-Z][A-Z0-9_]*\z/) and
      (is_nil(elem(entry, 1)) or argument?(elem(entry, 1)))
  end

  defp bounded?(value, maximum), do: is_integer(value) and value >= 1 and value <= maximum

  defp execute(guardian, step) do
    args =
      Enum.map([step.timeout_ms, step.output_bytes, step.cleanup_ms], &Integer.to_string/1) ++
        [step.cwd, step.executable | step.args]

    env =
      System.get_env()
      |> Map.new(fn {key, _} -> {key, nil} end)
      |> Map.merge(Map.new(step.env))
      |> Enum.map(fn {key, value} ->
        {String.to_charlist(key), if(is_nil(value), do: false, else: String.to_charlist(value))}
      end)

    port = Port.open({:spawn_executable, guardian}, [:binary, :exit_status, args: args, env: env])
    deadline = System.monotonic_time(:millisecond) + step.timeout_ms + step.cleanup_ms + 500

    try do
      collect(port, [], 0, step.output_bytes, deadline)
    after
      close_if_open(port)
    end
  rescue
    _ in [ArgumentError, ErlangError] -> failure(:command_setup_failed, <<>>, nil)
  end

  defp collect(port, chunks, size, limit, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, bytes}} when byte_size(bytes) + size <= limit ->
        collect(port, [bytes | chunks], size + byte_size(bytes), limit, deadline)

      {^port, {:data, _}} ->
        failure(:command_output_limit, output(chunks), nil)

      {^port, {:exit_status, status}} ->
        finish(status, output(chunks))
    after
      remaining -> failure(:command_deadline, output(chunks), nil)
    end
  end

  defp output(chunks) do
    ordered = Enum.reverse(chunks)
    IO.iodata_to_binary(ordered)
  end

  defp finish(0, bytes), do: {:ok, %{output: bytes, exit_status: 0}}
  defp finish(code, bytes), do: failure(Map.get(@codes, code, :command_failed), bytes, code)
  defp failure(code, bytes, status), do: {:error, code, %{output: bytes, exit_status: status}}

  # The child can exit between a liveness check and the close, so closing an
  # already closed Port counts as closed.
  defp close_if_open(port) do
    Port.close(port)
    :ok
  rescue
    ArgumentError -> :ok
  end
end
