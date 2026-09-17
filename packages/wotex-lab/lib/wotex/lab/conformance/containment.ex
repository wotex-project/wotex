defmodule Wotex.Lab.Conformance.Containment do
  @moduledoc """
  Host containment configuration for an external conformance target.

  The external runner owns the request/response protocol; this module wraps
  its executable in a host sandbox and an explicitly provisioned Rust
  supervisor. The wrapper applies inherited CPU, open-file and output-file
  limits, samples process-tree resident memory and process count against
  ceilings, runs the target in its own process group, enforces a
  deadline shorter than the runner deadline, and kills the process group on
  timeout or termination. The host sandbox denies networking and writes
  outside the caller-owned private temporary directory. On Linux, Bubblewrap
  mounts a private `/proc` and a minimal `/dev`; device nodes bound from the
  host are unusable inside its user namespace. The target environment selects the
  `C.UTF-8` locale, so a BEAM target keeps UTF-8 file name encoding on Linux.

  This profile admits reviewed local targets only. Sampling does not provide
  kernel-enforced memory/PID limits or proof against unobserved daemonization,
  and the write policy is not hostile-code read isolation.

  `external_map/5` refuses platforms without an admitted network sandbox. It
  returns runner configuration separately from a public, path-free evidence
  descriptor so executable and temporary paths never leak into evidence.
  """

  alias Wotex.Lab.Error

  @profile_version "2.0.2"
  @launcher_version "2.0.0"
  @runner_margin_ms 1_000
  @cleanup_reserve_ms 150
  @archive_placeholder "{subject_archive}"
  @option_keys ~w(timeout_ms max_output_bytes cpu_seconds memory_bytes processes open_files launcher)a
  @defaults %{
    timeout_ms: 10_000,
    max_output_bytes: 1_048_576,
    cpu_seconds: 8,
    memory_bytes: 8_589_934_592,
    processes: 64,
    open_files: 128
  }
  @ceilings %{
    timeout_ms: 120_000,
    max_output_bytes: 8_388_608,
    cpu_seconds: 120,
    memory_bytes: 34_359_738_368,
    processes: 1_024,
    open_files: 1_024
  }
  @minimum_memory 16_777_216

  @doc "The containment profile version and default resource limits."
  @spec profile() :: map()
  def profile, do: %{version: @profile_version, defaults: @defaults, ceilings: @ceilings}

  @doc """
  Builds an external-target map and a separate public containment descriptor.

  `executable`, `archive` and `temporary_directory` must be absolute existing
  paths. `args` must include `{subject_archive}` exactly once. The returned
  target map is suitable for `Wotex.Conformance.Target.External.from_map/1`.
  `:launcher` must be `%{executable: absolute_path, digest: "sha256:..."}` for
  the operator-provisioned `wotex-contained-exec` binary. No compiler, download,
  interpreter discovery or NIF loading occurs here. Keep that executable in an
  operator-owned location; digest admission is not protection against a host
  administrator replacing the file between validation and process startup.
  """
  @spec external_map(Path.t(), [String.t()], Path.t(), Path.t(), keyword()) ::
          {:ok, %{target: map(), evidence: map()}} | {:error, Error.t()}
  def external_map(executable, args, archive, temporary_directory, opts \\ []) do
    with :ok <- option_keys(opts),
         :ok <- regular(executable, :executable),
         :ok <- regular(archive, :archive),
         :ok <- directory(temporary_directory),
         :ok <- arguments(args),
         {:ok, limits} <- limits(opts),
         {:ok, launcher, launcher_digest} <- launcher(Keyword.get(opts, :launcher)),
         {:ok, sandbox} <- sandbox(temporary_directory),
         wrapper_args = wrapper_args(launcher, limits, temporary_directory, executable, args),
         {:ok, sandbox_args, mechanism} <-
           sandbox_args(sandbox, wrapper_args, temporary_directory) do
      {:ok,
       %{
         target: %{
           executable: sandbox,
           args: sandbox_args,
           artifact_path: archive,
           environment: %{
             "HOME" => temporary_directory,
             "TMPDIR" => temporary_directory,
             "LANG" => "C.UTF-8",
             "LC_ALL" => "C.UTF-8"
           },
           timeout_ms: limits.timeout_ms,
           max_output_bytes: limits.max_output_bytes
         },
         evidence: evidence(limits, mechanism, launcher_digest)
       }}
    end
  end

  defp option_keys(opts) do
    if Keyword.keyword?(opts) do
      keys = Keyword.keys(opts)
      unknown = keys -- @option_keys

      cond do
        length(keys) != length(Enum.uniq(keys)) ->
          invalid(:invalid_options, "containment options must not contain duplicate keys")

        unknown != [] ->
          invalid(:invalid_options, "containment options contain unknown keys", %{keys: unknown})

        true ->
          :ok
      end
    else
      invalid(:invalid_options, "containment options must be a keyword list")
    end
  end

  defp regular(path, field) when is_binary(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, mode: mode}} ->
        cond do
          Path.type(path) != :absolute ->
            invalid_file(field)

          field == :executable and Bitwise.band(mode, 0o111) == 0 ->
            invalid_file(field)

          true ->
            :ok
        end

      _ ->
        invalid_file(field)
    end
  end

  defp regular(_, field),
    do: invalid(:invalid_path, "containment path must be a string", %{field: field})

  defp invalid_file(field) do
    invalid(:invalid_path, "containment path is not an absolute regular file", %{field: field})
  end

  defp directory(path) when is_binary(path) do
    cond do
      Path.type(path) != :absolute ->
        invalid(:invalid_path, "temporary directory must be absolute", %{
          field: :temporary_directory
        })

      not File.dir?(path) ->
        invalid(:invalid_path, "temporary directory does not exist", %{
          field: :temporary_directory
        })

      unsafe_profile_path?(path) ->
        invalid(:invalid_path, "temporary directory cannot be represented by the host sandbox", %{
          field: :temporary_directory
        })

      true ->
        :ok
    end
  end

  defp directory(_),
    do:
      invalid(:invalid_path, "temporary directory must be a string", %{field: :temporary_directory})

  defp unsafe_profile_path?(path), do: String.contains?(path, ["\"", "\\", "\n", "\r", <<0>>])

  defp arguments(args) when is_list(args) and length(args) <= 28 do
    cond do
      Enum.any?(args, &(not is_binary(&1) or byte_size(&1) > 4_096)) ->
        invalid(:invalid_arguments, "target arguments must be bounded strings")

      Enum.count(args, &(&1 == @archive_placeholder)) != 1 ->
        invalid(:invalid_arguments, "target arguments require exactly one archive placeholder")

      Enum.any?(args, &(String.contains?(&1, @archive_placeholder) and &1 != @archive_placeholder)) ->
        invalid(:invalid_arguments, "archive placeholder must occupy one complete argument")

      true ->
        :ok
    end
  end

  defp arguments(_), do: invalid(:invalid_arguments, "target arguments must be a bounded list")

  defp limits(opts) do
    limits = Map.new(@defaults, fn {key, default} -> {key, Keyword.get(opts, key, default)} end)

    Enum.reduce_while(limits, {:ok, limits}, fn {key, value}, result ->
      minimum = if key == :memory_bytes, do: @minimum_memory, else: 1

      if is_integer(value) and value >= minimum and value <= Map.fetch!(@ceilings, key),
        do: {:cont, result},
        else:
          {:halt,
           invalid(:invalid_limit, "containment resource limit is outside its bound", %{limit: key})}
    end)
  end

  defp launcher(%{executable: path, digest: digest} = launcher) when map_size(launcher) == 2 do
    with true <- is_binary(path) and Path.type(path) == :absolute,
         true <-
           is_binary(digest) and byte_size(digest) == 71 and
             Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, digest),
         {:ok, %File.Stat{type: :regular, mode: mode, size: size}} <- File.lstat(path),
         true <- Bitwise.band(mode, 0o111) != 0 and size in 1..8_388_608,
         {:ok, bytes} when is_binary(bytes) <-
           File.open(path, [:read, :binary], &IO.binread(&1, 8_388_609)),
         true <- byte_size(bytes) <= 8_388_608 do
      actual = "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

      if actual == digest,
        do: {:ok, path, actual},
        else: invalid(:launcher_mismatch, "containment launcher digest does not match")
    else
      _ -> invalid(:invalid_launcher, "launcher must be a bounded, digest-pinned executable")
    end
  end

  defp launcher(nil),
    do: invalid(:unsupported, "an operator-provisioned native containment launcher is required")

  defp launcher(_), do: invalid(:invalid_launcher, "launcher descriptor is not admitted")

  defp sandbox(temporary_directory) do
    case :os.type() do
      {:unix, :darwin} -> admitted_executable("/usr/bin/sandbox-exec", temporary_directory)
      {:unix, _} -> linux_sandbox(temporary_directory)
      _ -> unsupported()
    end
  end

  defp linux_sandbox(temporary_directory) do
    case System.find_executable("bwrap") do
      nil -> unsupported()
      path -> admitted_executable(path, temporary_directory)
    end
  end

  defp admitted_executable(path, _) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular}} -> {:ok, path}
      _ -> unsupported()
    end
  end

  defp unsupported,
    do:
      {:error,
       Error.new(
         :unsupported,
         :containment,
         "host has no admitted no-network process sandbox"
       )}

  defp wrapper_args(launcher, limits, temporary_directory, executable, args) do
    wall_ms = inner_wall_ms(limits.timeout_ms)

    [
      launcher,
      "--wall-ms",
      Integer.to_string(wall_ms),
      "--cpu-seconds",
      Integer.to_string(limits.cpu_seconds),
      "--memory-bytes",
      Integer.to_string(limits.memory_bytes),
      "--processes",
      Integer.to_string(limits.processes),
      "--open-files",
      Integer.to_string(limits.open_files),
      "--file-size-bytes",
      Integer.to_string(limits.max_output_bytes),
      "--temp-dir",
      temporary_directory,
      "--",
      executable
      | args
    ]
  end

  defp sandbox_args("/usr/bin/sandbox-exec", wrapper_args, temporary_directory) do
    canonical_directory = darwin_canonical_directory(temporary_directory)

    profile =
      "(version 1)\n" <>
        "(allow default)\n" <>
        "(deny network*)\n" <>
        "(deny file-write*)\n" <>
        "(allow file-write* (subpath \"#{temporary_directory}\"))\n" <>
        "(allow file-write* (subpath \"#{canonical_directory}\"))\n"

    {:ok, ["-p", profile | wrapper_args], "darwin-sandbox-exec"}
  end

  defp sandbox_args(_, wrapper_args, temporary_directory) do
    args =
      [
        "--unshare-net",
        "--unshare-pid",
        "--die-with-parent",
        "--new-session",
        "--ro-bind",
        "/",
        "/",
        "--proc",
        "/proc",
        "--dev",
        "/dev",
        "--bind",
        temporary_directory,
        temporary_directory,
        "--chdir",
        temporary_directory,
        "--"
        | wrapper_args
      ]

    {:ok, args, "linux-bubblewrap"}
  end

  # Darwin presents temporary paths through `/var` while sandbox policy sees
  # their canonical `/private/var` spelling. Both remain the same private tree.
  defp darwin_canonical_directory("/var/" <> rest), do: "/private/var/" <> rest
  defp darwin_canonical_directory("/tmp/" <> rest), do: "/private/tmp/" <> rest
  defp darwin_canonical_directory(path), do: path

  defp evidence(limits, mechanism, launcher_digest) do
    %{
      "schema_version" => @profile_version,
      "kind" => "wotex_lab_conformance_containment",
      "mechanism" => mechanism,
      "network" => "denied",
      "temporary_directory" => "private",
      "termination" => "process_group",
      "launcher" => %{
        "implementation" => "rust-executable",
        "version" => @launcher_version,
        "digest" => launcher_digest
      },
      "limits" => %{
        "wall_ms" => inner_wall_ms(limits.timeout_ms),
        "runner_timeout_ms" => limits.timeout_ms,
        "runner_margin_ms" => runner_margin_ms(limits.timeout_ms),
        "cleanup_reserve_ms" => @cleanup_reserve_ms,
        "cpu_seconds" => limits.cpu_seconds,
        "memory_bytes" => limits.memory_bytes,
        "processes" => limits.processes,
        "open_files" => limits.open_files,
        "output_bytes" => limits.max_output_bytes
      }
    }
  end

  defp invalid(code, message, details \\ %{}),
    do: {:error, Error.new(code, :containment, message, details: details)}

  defp inner_wall_ms(runner_timeout_ms) do
    max(runner_timeout_ms - @runner_margin_ms, 1)
  end

  defp runner_margin_ms(runner_timeout_ms),
    do: runner_timeout_ms - inner_wall_ms(runner_timeout_ms)
end
