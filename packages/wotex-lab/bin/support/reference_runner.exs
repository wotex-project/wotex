defmodule Wotex.Lab.Check.ReferenceRunner do
  @moduledoc false

  alias Wotex.Lab.Check.ChildEnvironment
  alias Wotex.Lab.Evidence.Digest

  @marker ~r/\AWOTEX_REFERENCE_RUNNER cleanup=ok outcome=([a-z_]+) status=(\d{1,4}) output_bytes=(\d{1,8})\r?\n/
  @max_output_bytes 8_388_608

  @type result :: %{
          output: binary(),
          status: non_neg_integer(),
          outcome: String.t(),
          output_bytes: non_neg_integer(),
          cleanup: :ok
        }

  @spec build!(Path.t(), Path.t()) :: %{executable: Path.t(), digest: String.t()}
  def build!(root, work) do
    cargo = System.find_executable("cargo") || abort("cargo is required for the reference runner")
    manifest = Path.join(root, "priv/conformance/native/Cargo.toml")
    target = Path.join(work, "reference-runner-target")

    {output, status} =
      System.cmd(
        cargo,
        [
          "build",
          "--release",
          "--locked",
          "--bin",
          "wotex-reference-runner",
          "--manifest-path",
          manifest
        ],
        env: [{"CARGO_TARGET_DIR", target} | ChildEnvironment.scrubbed()],
        stderr_to_stdout: true
      )

    status == 0 || abort("reference runner build failed (#{status}):\n#{output}")
    executable = Path.join(target, "release/wotex-reference-runner")
    File.regular?(executable) || abort("reference runner build produced no executable")
    %{executable: executable, digest: Digest.file!(executable)}
  end

  @spec run!(map(), Path.t(), Path.t(), [String.t()], keyword()) :: result()
  def run!(runner, directory, executable, args, opts) do
    deadline_ms = Keyword.fetch!(opts, :deadline_ms)
    output_bytes = Keyword.get(opts, :output_bytes, @max_output_bytes)
    env = Keyword.get(opts, :env, [])
    temp_dir = Keyword.fetch!(opts, :temp_dir)

    valid_options?(deadline_ms, output_bytes, directory, executable, args, temp_dir) ||
      abort("invalid reference runner invocation")

    command = [
      "--wall-ms",
      Integer.to_string(deadline_ms),
      "--output-bytes",
      Integer.to_string(output_bytes),
      "--work-dir",
      Path.expand(directory),
      "--temp-dir",
      Path.expand(temp_dir),
      "--",
      Path.expand(executable)
      | args
    ]

    task =
      Task.async(fn ->
        System.cmd(runner.executable, command, env: env, stderr_to_stdout: true)
      end)

    outer_deadline = deadline_ms + 10_000

    case Task.yield(task, outer_deadline) || Task.shutdown(task, :brutal_kill) do
      {:ok, {encoded, status}} -> admit!(encoded, status, output_bytes)
      nil -> abort("native reference runner exceeded its fail-safe deadline")
    end
  end

  @spec admit(binary(), non_neg_integer(), pos_integer()) :: {:ok, result()} | {:error, atom()}
  def admit(encoded, status, max_output_bytes)
      when is_binary(encoded) and is_integer(status) and status >= 0 and
             is_integer(max_output_bytes) and max_output_bytes > 0 do
    case Regex.run(@marker, encoded) do
      [marker, outcome, encoded_status, encoded_bytes] ->
        output = binary_part(encoded, byte_size(marker), byte_size(encoded) - byte_size(marker))
        claimed_status = String.to_integer(encoded_status)
        claimed_bytes = String.to_integer(encoded_bytes)

        cond do
          claimed_status != status ->
            {:error, :status_mismatch}

          claimed_bytes != byte_size(output) ->
            {:error, :output_size_mismatch}

          claimed_bytes > max_output_bytes ->
            {:error, :output_limit_exceeded}

          true ->
            {:ok,
             %{
               output: output,
               status: status,
               outcome: outcome,
               output_bytes: claimed_bytes,
               cleanup: :ok
             }}
        end

      _ ->
        {:error, :invalid_runner_receipt}
    end
  end

  def admit(_, _, _), do: {:error, :invalid_runner_receipt}

  defp admit!(encoded, status, max_output_bytes) do
    case admit(encoded, status, max_output_bytes) do
      {:ok, result} -> result
      {:error, reason} -> abort("reference runner receipt is invalid: #{reason}")
    end
  end

  defp valid_options?(deadline_ms, output_bytes, directory, executable, args, temp_dir) do
    valid_bound?(deadline_ms, 1_800_000) and valid_bound?(output_bytes, @max_output_bytes) and
      valid_directory?(directory) and valid_directory?(temp_dir) and
      valid_executable?(executable) and valid_arguments?(args)
  end

  defp valid_bound?(value, maximum), do: is_integer(value) and value in 1..maximum
  defp valid_directory?(path), do: is_binary(path) and File.dir?(path)
  defp valid_executable?(path), do: is_binary(path) and File.regular?(path)

  defp valid_arguments?(args),
    do: is_list(args) and length(args) <= 119 and Enum.all?(args, &is_binary/1)

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end
