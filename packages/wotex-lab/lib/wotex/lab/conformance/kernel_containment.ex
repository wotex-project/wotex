defmodule Wotex.Lab.Conformance.KernelContainment do
  @moduledoc """
  Kernel-isolated containment for an untrusted external conformance target.

  This profile runs the target in a disposable OCI container through an
  operator-provisioned container runtime command line. Linux namespaces and
  cgroup v2 enforce what the reviewed-local `Wotex.Lab.Conformance.Containment`
  profile only samples: the memory ceiling (without swap) and process count are
  hard kernel limits, the network namespace has only loopback, the root
  filesystem is read-only, the only writable location is a bounded `tmpfs`,
  the target runs as user `65534:65534` with no capabilities and no privilege
  escalation, and only the subject archive and the explicitly listed code
  directories are visible from the host, all read-only.

  The container entrypoint is `/usr/bin/timeout --signal=KILL`, so the target's
  inner deadline is enforced as PID 1 of a private PID namespace. When that
  process exits, the kernel terminates every remaining process in the
  namespace, including detached or daemonized descendants. The inner deadline
  is three seconds shorter than the runner deadline, leaving room for container
  start, teardown and exit-status delivery. The default 15-second runner
  deadline is a fixed budget for stopping a hostile target, not a measured
  upper bound on honest work: container start and teardown dominate it on a
  loaded host, and the WLB.06 lane records the observed wall times instead of
  tightening it. Images are never pulled.

  `external_map/6` builds the conformance runner configuration, a path-free
  evidence descriptor and a random container label. `run_map/5` builds the same
  contained invocation for work that has no subject archive, such as a notebook
  evaluated from read-only mounts, and accepts `:network`. `:none`, the default,
  keeps the loopback-only network namespace; `{:internal, name}` instead joins an
  operator-created network that the caller must have created without egress, and
  the evidence names that variant so it is never read as `network=none` evidence. It validates files and digests and
  starts no process. `residue/3` and `release/3` are explicit, bounded runtime
  calls that count and force-remove any container still carrying that label.
  The container runtime daemon, its kernel and the pinned image remain trusted
  infrastructure; kernel exploits and runtime escape are outside this profile.

  The output byte limit is also the target's file-size resource limit. A BEAM
  target therefore needs `+JMsingle true`, because the default dual-mapped JIT
  sizes a memory file beyond that limit, and few scheduler threads, because
  threads count toward the process limit.
  """

  alias Wotex.Lab.Error

  @profile_version "1.1.0"
  @runner_margin_ms 3_000
  @archive_placeholder "{subject_archive}"
  @label_key "wotex.lab.containment"
  @max_runner_args 64
  @max_command_args 40
  @max_mounts 16
  @max_binds 17
  @max_runtime_bytes 134_217_728
  @option_keys ~w(timeout_ms max_output_bytes cpu_seconds cpu_millis memory_bytes processes open_files tmpfs_bytes network)a
  @network ~r|\A[a-z0-9][a-z0-9_.-]{0,62}\z|
  @defaults %{
    timeout_ms: 15_000,
    max_output_bytes: 1_048_576,
    cpu_seconds: 8,
    cpu_millis: 1_000,
    memory_bytes: 536_870_912,
    processes: 64,
    open_files: 128,
    tmpfs_bytes: 16_777_216
  }
  @minimums %{
    timeout_ms: 1,
    max_output_bytes: 1,
    cpu_seconds: 1,
    cpu_millis: 100,
    memory_bytes: 67_108_864,
    processes: 16,
    open_files: 16,
    tmpfs_bytes: 1_048_576
  }
  @ceilings %{
    timeout_ms: 120_000,
    max_output_bytes: 8_388_608,
    cpu_seconds: 120,
    cpu_millis: 16_000,
    memory_bytes: 8_589_934_592,
    processes: 1_024,
    open_files: 1_024,
    tmpfs_bytes: 268_435_456
  }

  @typedoc "An operator-provisioned runtime command line and digest-pinned image."
  @type runtime :: %{executable: Path.t(), digest: String.t(), image: String.t()}

  @doc "The kernel containment profile version, defaults, minimums and ceilings."
  @spec profile() :: map()
  def profile do
    %{
      version: @profile_version,
      runner_margin_ms: @runner_margin_ms,
      defaults: @defaults,
      minimums: @minimums,
      ceilings: @ceilings
    }
  end

  @doc """
  Builds an external-target map, a public evidence descriptor and a container label.

  `runtime` is `%{executable: absolute_path, digest: "sha256:...", image: "name@sha256:..."}`.
  The executable may be a symbolic link to a multi-call runtime binary; its
  resolved regular file must match `digest`. `command` is the argument vector
  inside the image: its first element is an absolute path and exactly one
  element is `{subject_archive}`. `archive` is an absolute regular file mounted
  read-only at the same path. `mounts` lists at most sixteen absolute host
  directories mounted read-only at the same paths. `temporary_directory` is a
  caller-owned private directory used as the runtime command's home.

  The returned target map is suitable for
  `Wotex.Conformance.Target.External.from_map/1`.
  """
  @spec external_map(runtime(), [String.t()], Path.t(), [Path.t()], Path.t(), keyword()) ::
          {:ok, %{target: map(), evidence: map(), label: String.t()}} | {:error, Error.t()}
  def external_map(runtime, command, archive, mounts, temporary_directory, opts \\ []) do
    with :ok <- option_keys(opts),
         :ok <- placeholder(command),
         :ok <- archive(archive),
         :ok <- mounts(mounts, @max_mounts),
         {:ok, invocation} <-
           contained(runtime, command, [archive | mounts], temporary_directory, opts) do
      {:ok,
       %{
         target: Map.put(invocation.run, :artifact_path, archive),
         evidence: invocation.evidence,
         label: invocation.label
       }}
    end
  end

  @doc """
  Builds a contained invocation for work that carries no subject archive.

  `subjects` lists at most sixteen absolute host files and directories, each
  mounted read-only at the same path; `command` needs no archive placeholder.
  The returned `:run` map holds the same executable, arguments, environment and
  bounds as a contained target, and the evidence names the network variant.
  """
  @spec run_map(runtime(), [String.t()], [Path.t()], Path.t(), keyword()) ::
          {:ok, %{run: map(), evidence: map(), label: String.t()}} | {:error, Error.t()}
  def run_map(runtime, command, subjects, temporary_directory, opts \\ []) do
    with :ok <- option_keys(opts),
         :ok <- subjects(subjects),
         do: contained(runtime, command, subjects, temporary_directory, opts)
  end

  defp subjects(subjects) when is_list(subjects) and subjects != [], do: :ok

  defp subjects(_),
    do: invalid(:invalid_path, "a contained run needs at least one subject", %{field: :mounts})

  defp contained(runtime, command, mounts, temporary_directory, opts) do
    with {:ok, limits} <- limits(opts),
         {:ok, network} <- network(opts),
         {:ok, executable, runtime_digest, image} <- runtime(runtime),
         :ok <- command(command),
         :ok <- mounts(mounts, @max_binds),
         :ok <- directory(temporary_directory),
         label = label(),
         args = run_args(image, command, mounts, limits, network, label),
         :ok <- argument_count(args) do
      {:ok,
       %{
         run: %{
           executable: executable,
           args: args,
           environment: %{
             "HOME" => temporary_directory,
             "LANG" => "C",
             "LC_ALL" => "C"
           },
           timeout_ms: limits.timeout_ms,
           max_output_bytes: limits.max_output_bytes
         },
         evidence: evidence(limits, runtime_digest, image, length(mounts), network),
         label: label
       }}
    end
  end

  defp network(opts) do
    case Keyword.get(opts, :network, :none) do
      :none ->
        {:ok, :none}

      {:internal, name} when is_binary(name) ->
        if Regex.match?(@network, name),
          do: {:ok, {:internal, name}},
          else: invalid(:invalid_options, "contained network name is not admitted")

      _ ->
        invalid(:invalid_options, "contained network must be none or an internal network")
    end
  end

  @doc """
  Counts containers that still carry `label`, using the runtime command line.

  The call runs one bounded runtime process with the caller's `temporary_directory`
  as its home and returns `{:error, %Wotex.Lab.Error{}}` when the runtime does not
  answer within `timeout_ms`.
  """
  @spec residue(Path.t(), String.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def residue(executable, label, opts) do
    with :ok <- label_value(label),
         {:ok, output} <-
           runtime_command(
             executable,
             ["ps", "--all", "--quiet", "--filter", "label=" <> @label_key <> "=" <> label],
             opts
           ) do
      {:ok, output |> String.split("\n", trim: true) |> length()}
    end
  end

  @doc """
  Force-removes containers carrying `label` and verifies that none remain.
  """
  @spec release(Path.t(), String.t(), keyword()) :: :ok | {:error, Error.t()}
  def release(executable, label, opts) do
    with :ok <- label_value(label),
         {:ok, output} <-
           runtime_command(
             executable,
             ["ps", "--all", "--quiet", "--filter", "label=" <> @label_key <> "=" <> label],
             opts
           ),
         ids = String.split(output, "\n", trim: true),
         :ok <- remove(executable, ids, opts),
         {:ok, 0} <- residue(executable, label, opts) do
      :ok
    else
      {:ok, remaining} when is_integer(remaining) ->
        invalid(:containment_residue, "contained targets remain after release", %{
          containers: remaining
        })

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp remove(_, [], _), do: :ok

  defp remove(executable, ids, opts) do
    with {:ok, _} <- runtime_command(executable, ["rm", "--force", "--volumes" | ids], opts),
         do: :ok
  end

  defp runtime_command(executable, args, opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 10_000)
    home = Keyword.get(opts, :temporary_directory)

    with :ok <- directory(home),
         true <- is_integer(timeout_ms) and timeout_ms in 1..60_000,
         {:ok, _, _} <- resolved_executable(executable) do
      port =
        Port.open({:spawn_executable, executable}, [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          args: args,
          env: [{~c"HOME", String.to_charlist(home)}, {~c"LANG", ~c"C"}, {~c"LC_ALL", ~c"C"}]
        ])

      collect(port, "", System.monotonic_time(:millisecond) + timeout_ms)
    else
      {:error, %Error{} = error} -> {:error, error}
      _ -> invalid(:invalid_options, "runtime command options are not admitted")
    end
  end

  defp collect(port, output, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, bytes}} when byte_size(output) + byte_size(bytes) <= 1_048_576 ->
        collect(port, output <> bytes, deadline)

      {^port, {:data, _}} ->
        close(port)
        invalid(:runtime_output_exceeded, "container runtime output exceeds its bound")

      {^port, {:exit_status, 0}} ->
        {:ok, output}

      {^port, {:exit_status, status}} ->
        invalid(:runtime_failed, "container runtime command failed", %{status: status})
    after
      remaining ->
        close(port)
        invalid(:runtime_timeout, "container runtime command did not answer in time")
    end
  end

  defp close(port) do
    Port.close(port)
  rescue
    ArgumentError -> :ok
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

  defp limits(opts) do
    limits = Map.new(@defaults, fn {key, default} -> {key, Keyword.get(opts, key, default)} end)

    Enum.reduce_while(limits, {:ok, limits}, fn {key, value}, result ->
      if is_integer(value) and value >= Map.fetch!(@minimums, key) and
           value <= Map.fetch!(@ceilings, key),
         do: {:cont, result},
         else:
           {:halt,
            invalid(:invalid_limit, "containment resource limit is outside its bound", %{
              limit: key
            })}
    end)
  end

  defp runtime(%{executable: executable, digest: digest, image: image} = runtime)
       when map_size(runtime) == 3 do
    with :ok <- image(image),
         {:ok, resolved, size} <- resolved_executable(executable),
         :ok <- digest_format(digest),
         {:ok, actual} <- file_digest(resolved, size) do
      if actual == digest,
        do: {:ok, executable, actual, image},
        else: invalid(:runtime_mismatch, "container runtime digest does not match")
    end
  end

  defp runtime(_),
    do: invalid(:invalid_runtime, "runtime must name an executable, its digest and an image")

  defp image(image) when is_binary(image) and byte_size(image) <= 256 do
    if Regex.match?(~r/\A[a-z0-9][a-z0-9._\/-]*@sha256:[0-9a-f]{64}\z/, image),
      do: :ok,
      else: invalid(:invalid_image, "image must be a digest-pinned reference")
  end

  defp image(_), do: invalid(:invalid_image, "image must be a digest-pinned reference")

  defp digest_format(digest) do
    if is_binary(digest) and Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, digest),
      do: :ok,
      else: invalid(:invalid_runtime, "runtime digest must be a lowercase sha256 digest")
  end

  defp resolved_executable(path) when is_binary(path) do
    if Path.type(path) == :absolute and not unsafe?(path),
      do: resolve(path, 8),
      else: invalid(:invalid_runtime, "runtime executable must be an absolute path")
  end

  defp resolved_executable(_),
    do: invalid(:invalid_runtime, "runtime executable must be an absolute path")

  defp resolve(_, 0), do: invalid(:invalid_runtime, "runtime executable link chain is too deep")

  defp resolve(path, depth) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :symlink}} ->
        case :file.read_link_all(path) do
          {:ok, target} -> resolve(Path.expand(to_string(target), Path.dirname(path)), depth - 1)
          _ -> invalid(:invalid_runtime, "runtime executable link cannot be read")
        end

      {:ok, %File.Stat{type: :regular, mode: mode, size: size}}
      when size in 1..@max_runtime_bytes ->
        if Bitwise.band(mode, 0o111) != 0,
          do: {:ok, path, size},
          else: invalid(:invalid_runtime, "runtime executable is not executable")

      _ ->
        invalid(:invalid_runtime, "runtime executable is not a bounded regular file")
    end
  end

  defp file_digest(path, size) do
    case File.open(path, [:read, :binary], &IO.binread(&1, size + 1)) do
      {:ok, bytes} when is_binary(bytes) and byte_size(bytes) == size ->
        {:ok, "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)}

      _ ->
        invalid(:invalid_runtime, "runtime executable changed while it was read")
    end
  end

  defp command([first | _] = command) when length(command) <= @max_command_args do
    cond do
      Enum.any?(command, &(not is_binary(&1) or byte_size(&1) > 4_096 or not String.valid?(&1))) ->
        invalid(:invalid_arguments, "contained command must contain bounded strings")

      Path.type(first) != :absolute or first == @archive_placeholder ->
        invalid(:invalid_arguments, "contained command must start with an absolute path")

      true ->
        :ok
    end
  end

  defp command(_), do: invalid(:invalid_arguments, "contained command must be a bounded list")

  defp placeholder(command) when is_list(command) do
    cond do
      Enum.count(command, &(&1 == @archive_placeholder)) != 1 ->
        invalid(:invalid_arguments, "contained command requires exactly one archive placeholder")

      Enum.any?(
        command,
        &(is_binary(&1) and String.contains?(&1, @archive_placeholder) and
              &1 != @archive_placeholder)
      ) ->
        invalid(:invalid_arguments, "archive placeholder must occupy one complete argument")

      true ->
        :ok
    end
  end

  defp placeholder(_), do: invalid(:invalid_arguments, "contained command must be a bounded list")

  defp archive(path) when is_binary(path) do
    with true <- Path.type(path) == :absolute and not unsafe?(path),
         {:ok, %File.Stat{type: :regular}} <- File.lstat(path) do
      :ok
    else
      _ -> invalid(:invalid_path, "archive must be an absolute regular file", %{field: :archive})
    end
  end

  defp archive(_),
    do: invalid(:invalid_path, "archive must be an absolute regular file", %{field: :archive})

  defp mounts(mounts, ceiling) when is_list(mounts) and length(mounts) <= ceiling do
    cond do
      length(mounts) != length(Enum.uniq(mounts)) ->
        invalid(:invalid_path, "mounts must be distinct", %{field: :mounts})

      Enum.all?(mounts, &mount?/1) ->
        :ok

      true ->
        invalid(:invalid_path, "mounts must be absolute existing files or directories", %{
          field: :mounts
        })
    end
  end

  defp mounts(_, _),
    do: invalid(:invalid_path, "mounts must be a bounded list", %{field: :mounts})

  defp mount?(path) when is_binary(path) do
    Path.type(path) == :absolute and path != "/" and not unsafe?(path) and
      match?({:ok, %File.Stat{type: type}} when type in [:directory, :regular], File.lstat(path))
  end

  defp mount?(_), do: false

  defp directory(path) when is_binary(path) do
    if Path.type(path) == :absolute and not unsafe?(path) and File.dir?(path),
      do: :ok,
      else:
        invalid(:invalid_path, "temporary directory must be an absolute existing directory", %{
          field: :temporary_directory
        })
  end

  defp directory(_),
    do:
      invalid(:invalid_path, "temporary directory must be an absolute existing directory", %{
        field: :temporary_directory
      })

  # Runtime mount and environment options are comma and equals separated.
  defp unsafe?(path),
    do: byte_size(path) > 4_096 or String.contains?(path, [",", "=", "\n", "\r", <<0>>])

  defp label, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

  defp label_value(label) do
    if is_binary(label) and Regex.match?(~r/\A[0-9a-f]{32}\z/, label),
      do: :ok,
      else: invalid(:invalid_label, "container label is not admitted")
  end

  defp argument_count(args) do
    if length(args) <= @max_runner_args,
      do: :ok,
      else:
        invalid(:invalid_arguments, "contained invocation exceeds the runner argument limit", %{
          arguments: length(args)
        })
  end

  defp run_args(image, command, mounts, limits, network, label) do
    [
      "run",
      "--rm",
      "--interactive",
      "--pull=never",
      "--label=" <> @label_key <> "=" <> label,
      network_arg(network),
      "--read-only",
      "--tmpfs=/tmp:rw,nosuid,nodev,noexec,size=#{limits.tmpfs_bytes}",
      "--cap-drop=ALL",
      "--security-opt=no-new-privileges",
      "--user=65534:65534",
      "--workdir=/tmp",
      "--env=HOME=/tmp",
      "--env=TMPDIR=/tmp",
      "--env=LANG=C.UTF-8",
      "--env=LC_ALL=C.UTF-8",
      "--memory=#{limits.memory_bytes}",
      "--memory-swap=#{limits.memory_bytes}",
      "--pids-limit=#{limits.processes}",
      "--cpus=#{cpus(limits.cpu_millis)}",
      "--ulimit=cpu=#{limits.cpu_seconds}:#{limits.cpu_seconds}",
      "--ulimit=nofile=#{limits.open_files}:#{limits.open_files}",
      "--ulimit=fsize=#{limits.max_output_bytes}:#{limits.max_output_bytes}",
      "--ulimit=core=0:0"
    ] ++
      Enum.map(mounts, &bind/1) ++
      [
        "--entrypoint=/usr/bin/timeout",
        image,
        "--signal=KILL",
        seconds(inner_wall_ms(limits.timeout_ms))
      ] ++ command
  end

  defp bind(path), do: "--mount=type=bind,source=#{path},target=#{path},readonly"

  defp network_arg(:none), do: "--network=none"
  defp network_arg({:internal, name}), do: "--network=" <> name

  defp cpus(millis),
    do:
      "#{div(millis, 1_000)}.#{millis |> rem(1_000) |> Integer.to_string() |> String.pad_leading(3, "0")}"

  defp seconds(ms),
    do: "#{div(ms, 1_000)}.#{ms |> rem(1_000) |> Integer.to_string() |> String.pad_leading(3, "0")}"

  defp evidence(limits, runtime_digest, image, host_mounts, network) do
    %{
      "schema_version" => @profile_version,
      "kind" => "wotex_lab_conformance_kernel_containment",
      "mechanism" => "oci-linux-namespaces-cgroup-v2",
      "network" => network_evidence(network),
      "root_filesystem" => "read-only",
      "writable" => "tmpfs",
      "host_mounts" => %{"mode" => "read-only", "count" => host_mounts},
      "user" => "65534:65534",
      "capabilities" => "none",
      "privilege_escalation" => "denied",
      "image" => %{"reference" => image, "pull" => "never"},
      "runtime" => %{"digest" => runtime_digest},
      "termination" => "pid-namespace-init",
      "limits" => %{
        "wall_ms" => inner_wall_ms(limits.timeout_ms),
        "runner_timeout_ms" => limits.timeout_ms,
        "runner_margin_ms" => limits.timeout_ms - inner_wall_ms(limits.timeout_ms),
        "memory_bytes" => limits.memory_bytes,
        "swap_bytes" => 0,
        "processes" => limits.processes,
        "cpu_millis" => limits.cpu_millis,
        "cpu_seconds" => limits.cpu_seconds,
        "open_files" => limits.open_files,
        "output_bytes" => limits.max_output_bytes,
        "tmpfs_bytes" => limits.tmpfs_bytes
      }
    }
  end

  defp network_evidence(:none), do: "none"
  defp network_evidence({:internal, name}), do: "internal:" <> name

  defp inner_wall_ms(runner_timeout_ms), do: max(runner_timeout_ms - @runner_margin_ms, 1)

  defp invalid(code, message, details \\ %{}),
    do: {:error, Error.new(code, :containment, message, details: details)}
end
