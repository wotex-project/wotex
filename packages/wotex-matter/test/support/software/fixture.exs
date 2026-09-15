Code.require_file("manifest.exs", __DIR__)
Code.require_file("build.exs", __DIR__)
Code.require_file("run.exs", __DIR__)

defmodule Wotex.Matter.SoftwareFixture do
  @moduledoc false

  alias Wotex.Matter.{SoftwareBuild, SoftwareManifest, SoftwareRun}

  @spec main(:native_build | :software_build | :run, [String.t()]) :: :ok
  def main(operation, arguments) when operation in [:native_build, :software_build] do
    root = File.cwd!()
    workspace = SoftwareManifest.arguments(arguments, root)
    mode = if operation == :native_build, do: :native, else: :software
    prepare(workspace)
    watcher = acquire(workspace)

    try do
      build(root, workspace, mode)
    after
      release(watcher)
    end

    Mix.shell().info("Matter #{operation} completed: #{workspace}")
    :ok
  end

  def main(:run, arguments) do
    root = File.cwd!()
    workspace = SoftwareManifest.arguments(arguments, root)
    manifest = SoftwareManifest.read(Path.join(workspace, "workspace-manifest.json"))
    watcher = acquire(workspace)

    try do
      SoftwareManifest.verify_local(root, workspace, manifest, :software)
      SoftwareRun.run(root, workspace)
    after
      release(watcher)
    end
  end

  defp prepare(workspace) do
    case File.ls(workspace) do
      {:error, :enoent} ->
        File.mkdir!(workspace)

      {:ok, []} ->
        :ok

      {:ok, entries} ->
        unless "workspace-manifest.json" in entries, do: fail(:unrelated_workspace)

      _ ->
        fail(:invalid_workspace)
    end
  end

  defp build(root, workspace, mode) do
    path = Path.join(workspace, "workspace-manifest.json")

    if File.exists?(path) do
      SoftwareManifest.verify_local(root, workspace, SoftwareManifest.read(path), mode)
    else
      source = SoftwareManifest.identity(root)

      try do
        native = SoftwareBuild.run(root, workspace, mode)
        unless SoftwareManifest.identity(root) == source, do: fail(:source_changed_during_build)

        value = %{
          "schema" => "wotex.matter.software-workspace@1",
          "status" => "ready",
          "mode" => Atom.to_string(mode),
          "source_revision" => native["source_revision"],
          "source" => source,
          "sdk_revision" => SoftwareManifest.sdk_revision(),
          "sdk_archive_sha256" => SoftwareManifest.sdk_sha256(),
          "container_image" => SoftwareManifest.image(),
          "target" => "x86_64-linux-gnu",
          "files" => SoftwareManifest.file_hashes(workspace, Atom.to_string(mode))
        }

        SoftwareManifest.write(path, value)
        SoftwareManifest.verify_local(root, workspace, SoftwareManifest.read(path), mode)
      rescue
        _error ->
          SoftwareManifest.write(Path.join(workspace, "build-result.json"), %{
            "schema" => "wotex.matter.software-build@1",
            "status" => "failed"
          })

          reraise Mix.Error, [message: "software_build_failed"], __STACKTRACE__
      end
    end
  end

  defp acquire(workspace) do
    path = workspace <> ".lock"
    unless File.mkdir(path) == :ok, do: fail(:workspace_locked)
    owner = self()

    spawn(fn ->
      monitor = Process.monitor(owner)

      receive do
        {:release, sender} ->
          Process.demonitor(monitor, [:flush])
          send(sender, {:lock_released, self(), File.rmdir(path)})

        {:DOWN, ^monitor, :process, ^owner, _} ->
          File.rmdir(path)
      end
    end)
  end

  defp release(watcher) do
    send(watcher, {:release, self()})

    receive do
      {:lock_released, ^watcher, :ok} -> :ok
      {:lock_released, ^watcher, _} -> fail(:workspace_unlock_failed)
    after
      5_000 -> fail(:workspace_unlock_failed)
    end
  end

  defp fail(code), do: Mix.raise(Atom.to_string(code))
end
