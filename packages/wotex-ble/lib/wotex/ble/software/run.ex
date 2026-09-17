defmodule Wotex.BLE.Software.Run do
  @moduledoc """
  Runs the public BlueZ virtual-controller software lanes from a built workspace.

  `run/1` is invoked by `mix wotex.software.run --workspace ABSOLUTE_PATH`. It
  first verifies the complete software build read-only, then boots one fresh
  QEMU guest per BEAM lane from a copy-on-write overlay of `rootfs.raw`. Each
  guest starts two virtual LE controllers, a private D-Bus daemon, `bluetoothd`,
  `btmon` and the independent GATT peer, then runs the public BLE and Runtime
  interoperability tests against the Mix-built native host.

  Every lane has a unique owned container name, a ten-minute guest bound and a
  retained result directory under `runs/`. Owned containers are removed and
  counted after every lane, including failures. A lane passes only when the
  guest reports zero remaining owned processes and virtual controllers, the
  console has no kernel panic, the GATT peer reports clean release, and ExUnit
  records exactly the literal public test count as passed with no other status.
  `result.json` records the verified build manifest digest, lane evidence
  digests and cleanup counts. Virtual controllers are software radios, not
  physical RF evidence.
  """

  alias Wotex.BLE.Software.{Build, Fixture, Operations}

  @lanes ~w(latest lower)
  @evidence ~w(console.log runtime.log exunit.log exunit.json peer.log public-peer-result.json
    guest-result.json btvirt.log dbus.log bluetoothd.log btmon.log wire.btsnoop)

  @doc "Validates the exact task argument vector before any run I/O."
  @spec arguments(term()) :: {:ok, String.t()} | {:error, :invalid_native_build_arguments}
  defdelegate arguments(args), to: Build

  @doc "Runs both software lanes and returns the retained result directory."
  @spec run(String.t()) :: {:ok, map()} | {:error, term()}
  def run(workspace), do: run(workspace, File.cwd!(), Operations)

  @doc false
  @spec run(term(), term(), module()) :: {:ok, map()} | {:error, term()}
  def run(workspace, root, operations)
      when is_binary(workspace) and is_binary(root) and is_atom(operations) do
    with {:ok, manifest} <- Build.verified(workspace, root, operations),
         {:ok, expected} <-
           Fixture.public_case_count(Path.join(workspace, "context/public/source/wotex-ble")),
         {:ok, directory} <- run_directory(workspace) do
      context = %{
        workspace: workspace,
        tools: manifest["identity"]["tools"],
        image: manifest["images"]["public"]["id"],
        directory: directory,
        expected: expected
      }

      lanes = Enum.map(@lanes, &lane(context, operations, &1))
      finish(context, manifest, lanes, operations)
    end
  end

  def run(_, _, _), do: {:error, :invalid_build_workspace}

  @doc false
  @spec evaluate(String.t(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def evaluate(directory, expected) do
    with {:ok, guest} <- json(directory, "guest-result.json"),
         true <-
           guest == %{
             "result" => 0,
             "owned_processes_remaining" => 0,
             "virtual_controllers_remaining" => 0
           } || {:error, {:guest_failed, guest}},
         {:ok, console} <- File.read(Path.join(directory, "console.log")),
         false <- String.contains?(console, "Kernel panic") && {:error, :kernel_panic},
         {:ok, peer} <- json(directory, "public-peer-result.json"),
         true <- peer["clean"] == true || {:error, :peer_not_released},
         {:ok, report} <- json(directory, "exunit.json"),
         true <-
           report["counts"] == %{"passed" => expected} || {:error, {:exunit, report["counts"]}},
         true <- length(report["cases"] || []) == expected || {:error, :exunit_case_count} do
      {:ok, %{"exunit" => report["counts"], "peer" => peer["statistics"]}}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_lane_evidence}
    end
  end

  defp run_directory(workspace) do
    directory =
      Path.join([
        workspace,
        "runs",
        "run-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      ])

    with :ok <- File.mkdir_p(Path.dirname(directory)),
         :ok <- File.mkdir(directory) do
      {:ok, directory}
    else
      _ -> {:error, :software_run_filesystem}
    end
  end

  defp lane(context, operations, lane) do
    directory = Path.join(context.directory, lane)
    guest = "wotex-ble-software-guest-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    names = [guest, guest <> "-disk"]
    lane_context = Map.put(context, :logs, directory)
    started = System.monotonic_time(:millisecond)

    outcome =
      with :ok <- File.mkdir(directory),
           :ok <- File.write(Path.join(directory, "lane"), lane),
           {:ok, _} <- disk(lane_context, operations, guest, lane),
           {:ok, _} <- boot(lane_context, operations, guest, lane) do
        evaluate(directory, context.expected)
      end

    remaining = cleanup(lane_context, operations, names)
    File.rm(Path.join(directory, "disk.qcow2"))
    elapsed = System.monotonic_time(:millisecond) - started

    record = %{
      "lane" => lane,
      "elapsed_ms" => elapsed,
      "containers_remaining" => remaining,
      "evidence" => evidence(directory, operations)
    }

    case outcome do
      {:ok, observed} when remaining == 0 ->
        Map.merge(record, %{"status" => "passed"} |> Map.merge(observed))

      {:ok, _} ->
        Map.put(record, "status", "failed") |> Map.put("reason", "container_cleanup")

      {:error, reason} ->
        Map.merge(record, %{"status" => "failed", "reason" => inspect(reason)})
    end
  end

  defp disk(context, operations, guest, lane) do
    relative = Path.relative_to(Path.join(context.directory, lane), context.workspace)

    args = [
      "run",
      "--rm",
      "--name",
      guest <> "-disk",
      "--network",
      "none",
      "--mount",
      mount(context),
      context.image,
      "qemu-img",
      "create",
      "-f",
      "qcow2",
      "-F",
      "raw",
      "-b",
      "/work/rootfs.raw",
      "/work/#{relative}/disk.qcow2"
    ]

    Build.docker(context, operations, :disk, args, 60_000)
  end

  defp boot(context, operations, guest, lane) do
    relative = Path.relative_to(Path.join(context.directory, lane), context.workspace)

    Build.docker(
      context,
      operations,
      :console,
      [
        "run",
        "--rm",
        "--name",
        guest,
        "--network",
        "none",
        "--mount",
        mount(context),
        context.image
      ] ++
        ~w(qemu-system-aarch64 -M virt-7.2 -cpu cortex-a57 -accel tcg -smp 4 -m 2048 -nographic -no-reboot -nic none) ++
        ["-kernel", "/boot/vmlinuz-6.1.0-53-arm64", "-initrd", "/boot/initrd.img-6.1.0-53-arm64"] ++
        ["-append", "console=ttyAMA0 root=/dev/vda rw noresume init=/bootstrap.sh"] ++
        ["-drive", "file=/work/#{relative}/disk.qcow2,format=qcow2,if=virtio"] ++
        ["-fsdev", "local,id=fixture,path=/work/#{relative},security_model=none"] ++
        ["-device", "virtio-9p-pci,fsdev=fixture,mount_tag=fixture"],
      600_000
    )
  end

  defp mount(context), do: "type=bind,src=#{context.workspace},target=/work"

  defp cleanup(context, operations, names) do
    Enum.count(names, fn name ->
      filter = ["ps", "-aq", "--filter", "name=^/#{name}$"]

      case Build.docker(context, operations, :cleanup_list, filter, 60_000) do
        {:ok, present} ->
          if String.trim(present) != "",
            do: Build.docker(context, operations, :cleanup_remove, ["rm", "-f", name], 60_000)

          remaining?(Build.docker(context, operations, :cleanup_verify, filter, 60_000))

        _ ->
          true
      end
    end)
  end

  defp remaining?({:ok, output}), do: String.trim(output) != ""
  defp remaining?(_), do: true

  defp evidence(directory, operations) do
    for name <- @evidence,
        path = Path.join(directory, name),
        match?({:ok, %File.Stat{type: :regular}}, File.lstat(path)),
        {:ok, digest} <- [operations.digest(path)],
        into: %{},
        do: {name, digest}
  end

  defp json(directory, name) do
    with {:ok, bytes} <- File.read(Path.join(directory, name)),
         {:ok, value} when is_map(value) <- Jason.decode(bytes) do
      {:ok, value}
    else
      _ -> {:error, {:missing_lane_evidence, name}}
    end
  end

  defp finish(context, manifest, lanes, operations) do
    {:ok, build} = operations.digest(Path.join(context.workspace, "software-manifest.json"))

    result = %{
      "schema" => "wotex.ble.software-run",
      "version" => 1,
      "build_manifest_sha256" => build,
      "native_host_sha256" =>
        Enum.find_value(
          manifest["native"]["binaries"],
          &(&1["purpose"] == "sdk_host" && &1["sha256"])
        ),
      "expected_cases" => context.expected,
      "lanes" => lanes,
      "result" => if(Enum.all?(lanes, &(&1["status"] == "passed")), do: "passed", else: "failed")
    }

    File.write!(Path.join(context.directory, "result.json"), Jason.encode!(result) <> "\n")

    if result["result"] == "passed",
      do: {:ok, Map.put(result, "directory", context.directory)},
      else: {:error, {:software_run_failed, context.directory}}
  end
end
