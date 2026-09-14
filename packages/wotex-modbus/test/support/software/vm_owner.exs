Code.require_file("fixture.exs", __DIR__)

[workspace, root, lane, ready_path] =
  case System.argv() do
    ["--" | arguments] -> arguments
    arguments -> arguments
  end

File.mkdir_p!(lane)

manifest =
  Wotex.Modbus.SoftwareManifest.read(Path.join(workspace, "peer-manifest.json"))

context = %{
  root: root,
  workspace: workspace,
  lane: lane,
  guardian: Path.join(workspace, "command"),
  docker: System.find_executable("docker"),
  manifest: manifest,
  run_id: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower),
  after_open: fn cid ->
    File.write!(ready_path, cid <> "\n", [:exclusive])
    Process.sleep(:infinity)
  end
}

Wotex.Modbus.SoftwareRun.start_peer(context)
