defmodule Wotex.Lab.HostedArtifactTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Mix.Tasks.Wotex.Lab.Hosted.Artifact

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "wotex-hosted-artifact-test-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      workspace: Path.join(root, "artifact"),
      second_workspace: Path.join(root, "artifact-repeat")
    }
  end

  test "argument admission is closed and requires absolute paths", %{workspace: workspace} do
    runtime = runtime!()

    assert {^workspace, ^runtime} =
             Artifact.arguments(["--workspace", workspace, "--runtime", runtime])

    for args <- [
          [],
          ["--workspace", workspace],
          ["--runtime", runtime],
          ["--workspace", workspace, "--runtime", runtime, "extra"],
          ["--workspace", workspace, "--runtime", runtime, "--unknown", "x"]
        ] do
      assert_raise Mix.Error, fn -> Artifact.arguments(args) end
    end
  end

  test "Escript normalization rejects malformed and duplicate archive entries", %{root: root} do
    malformed = Path.join(root, "malformed")
    File.write!(malformed, "not-an-escript", [:exclusive])

    assert_raise Mix.Error, ~r/could not be normalized/, fn ->
      Artifact.normalize_escript!(malformed)
    end

    duplicate = Path.join(root, "duplicate")
    write_escript!(duplicate, [{~c"main.beam", "first"}, {~c"main.beam", "second"}])

    assert_raise Mix.Error, ~r/duplicate paths/, fn ->
      Artifact.normalize_escript!(duplicate)
    end

    absolute = Path.join(root, "absolute")
    write_escript!(absolute, [{~c"main.beam", "body"}])

    absolute
    |> File.read!()
    |> String.replace("main.beam", "../x.beam")
    |> then(&File.write!(absolute, &1))

    assert_raise Mix.Error, ~r/entry is invalid/, fn ->
      Artifact.normalize_escript!(absolute)
    end
  end

  test "Escript normalization admits a bounded ZIP data descriptor", %{root: root} do
    data_descriptor = Path.join(root, "data-descriptor")

    write_escript!(data_descriptor, [{~c"main.beam", "body"}], data_descriptor: true)

    assert_raise Mix.Error, ~r/missing a required entry/, fn ->
      Artifact.normalize_escript!(data_descriptor)
    end
  end

  test "Escript normalization accepts central-directory entries in a different order", %{root: root} do
    path = Path.join(root, "reordered-directory")

    entries =
      Enum.map(
        [
          "nil_escript.beam",
          "wotex_lab/ebin/Elixir.Wotex.Lab.Error.beam",
          "wotex_lab/ebin/Elixir.Wotex.Lab.Metrics.Catalogue.beam",
          "wotex_lab/ebin/Elixir.Wotex.Lab.Metrics.Query.beam",
          "wotex_lab/ebin/Elixir.Wotex.Lab.Options.beam",
          "wotex_lab/ebin/Elixir.Wotex.Lab.Telemetry.beam",
          "wotex_lab_workbench/ebin/Elixir.WotexLabWorkbench.Investigation.BeamlensSupervisor.beam",
          "wotex_lab_workbench/ebin/Elixir.WotexLabWorkbench.Investigation.ContextStore.beam",
          "wotex_lab_workbench/ebin/Elixir.WotexLabWorkbench.Investigation.HostedSkill.beam",
          "wotex_lab_workbench/ebin/Elixir.WotexLabWorkbench.Investigation.HostedWorker.beam",
          "wotex_lab_workbench/ebin/Elixir.WotexLabWorkbench.Investigation.OperatorRunner.beam"
        ],
        &{String.to_charlist(&1), "beam"}
      )

    write_escript!(path, entries)
    reorder_central_directory!(path)

    assert :ok = Artifact.normalize_escript!(path)
  end

  @tag :integration
  @tag timeout: 300_000
  test "the source build qualifies its exact outputs and rejects mutation", %{
    workspace: workspace,
    second_workspace: second_workspace
  } do
    runtime = runtime!()
    assert :ok = Artifact.build(workspace, runtime)

    manifest =
      workspace
      |> Path.join("native-build.json")
      |> File.read!()
      |> Jason.decode!()

    assert manifest["schema_version"] == "wotex-lab-hosted-artifact/v1"
    assert manifest["build_environment"] == "dev"
    assert manifest["cargo_version"] == "cargo 1.97.1 (c980f4866 2026-06-30)"
    assert manifest["elixir_version"] == "1.20.2"
    assert manifest["otp_release"] == "29"
    assert manifest["rustc_version"] == "rustc 1.97.1 (8bab26f4f 2026-07-14)"
    assert manifest["runtime"]["sha256"] =~ ~r/\Asha256:[0-9a-f]{64}\z/

    assert Enum.map(manifest["precompiled_inputs"], & &1["dependency"]) == [
             "baml_elixir",
             "ex_maude",
             "explorer"
           ]

    assert Enum.all?(manifest["precompiled_inputs"], fn input ->
             input["sha256"] =~ ~r/\Asha256:[0-9a-f]{64}\z/ and input["size"] > 0
           end)

    assert Enum.map(manifest["outputs"], & &1["path"]) == [
             "output/bin/wotex-hosted-investigation-runner",
             "output/bin/wotex-lab-hosted-worker"
           ]

    entries =
      workspace
      |> Path.join("output/bin/wotex-lab-hosted-worker")
      |> escript_entries!()

    refute Enum.any?(entries, &String.starts_with?(&1, "makeup/"))
    refute Enum.any?(entries, &String.starts_with?(&1, "nx/"))
    refute "puck/ebin/Elixir.Puck.Baml.beam" in entries

    assert Enum.filter(entries, &String.starts_with?(&1, "wotex_lab_workbench/")) == [
             "wotex_lab_workbench/ebin/Elixir.WotexLabWorkbench.Investigation.BeamlensSupervisor.beam",
             "wotex_lab_workbench/ebin/Elixir.WotexLabWorkbench.Investigation.ContextStore.beam",
             "wotex_lab_workbench/ebin/Elixir.WotexLabWorkbench.Investigation.HostedSkill.beam",
             "wotex_lab_workbench/ebin/Elixir.WotexLabWorkbench.Investigation.HostedWorker.beam",
             "wotex_lab_workbench/ebin/Elixir.WotexLabWorkbench.Investigation.OperatorRunner.beam"
           ]

    assert :ok = Artifact.check(workspace, runtime)

    with_environment(
      %{
        "ERL_COMPILER_OPTIONS" => "[debug_info]",
        "RUSTFLAGS" => "-C debuginfo=2",
        "CFLAGS" => "-DWOTEX_AMBIENT_FLAG=1"
      },
      fn -> assert :ok = Artifact.build(second_workspace, runtime) end
    )

    repeated =
      second_workspace
      |> Path.join("native-build.json")
      |> File.read!()
      |> Jason.decode!()

    assert repeated == manifest

    worker = Path.join(workspace, "output/bin/wotex-lab-hosted-worker")
    File.write!(worker, "changed", [:append])

    assert_raise Mix.Error, ~r/output digest changed/, fn ->
      Artifact.check(workspace, runtime)
    end

    assert_raise Mix.Error, ~r/workspace already exists/, fn ->
      Artifact.build(workspace, runtime)
    end
  end

  defp runtime! do
    case System.find_executable("escript") do
      nil -> flunk("escript runtime is unavailable")
      runtime -> runtime
    end
  end

  defp write_escript!(path, entries, options \\ []) do
    {:ok, {_, archive}} = :zip.create(~c"worker.zip", entries, [:memory])
    archive = if options[:data_descriptor], do: with_data_descriptor!(archive), else: archive

    :ok =
      :escript.create(String.to_charlist(path),
        shebang: :default,
        comment: [],
        emu_args: ~c"-escript main main",
        archive: archive
      )
  end

  defp with_data_descriptor!(archive) do
    [{eocd_offset, 4}] = :binary.matches(archive, <<0x50, 0x4B, 0x05, 0x06>>)
    eocd = binary_part(archive, eocd_offset, byte_size(archive) - eocd_offset)

    <<0x06054B50::little-32, disk::little-16, central_disk::little-16, disk_entries::little-16,
      entries::little-16, central_size::little-32, central_offset::little-32,
      comment_size::little-16, comment::binary>> = eocd

    local = binary_part(archive, 0, central_offset)
    central = binary_part(archive, central_offset, central_size)

    <<0x04034B50::little-32, version::little-16, flags::little-16, compression::little-16,
      modified_time::little-16, modified_date::little-16, crc::little-32,
      compressed_size::little-32, uncompressed_size::little-32, name_size::little-16,
      extra_size::little-16, body::binary>> = local

    descriptor_flags = Bitwise.bor(flags, 0x0008)

    normalized_local =
      <<0x04034B50::little-32, version::little-16, descriptor_flags::little-16,
        compression::little-16, modified_time::little-16, modified_date::little-16, 0::little-32,
        0::little-32, 0::little-32, name_size::little-16, extra_size::little-16, body::binary,
        0x08074B50::little-32, crc::little-32, compressed_size::little-32,
        uncompressed_size::little-32>>

    <<0x02014B50::little-32, made_by::little-16, required::little-16, _::little-16,
      central_tail::binary>> = central

    normalized_central =
      <<0x02014B50::little-32, made_by::little-16, required::little-16, descriptor_flags::little-16,
        central_tail::binary>>

    normalized_eocd =
      <<0x06054B50::little-32, disk::little-16, central_disk::little-16, disk_entries::little-16,
        entries::little-16, central_size::little-32, byte_size(normalized_local)::little-32,
        comment_size::little-16, comment::binary>>

    normalized_local <> normalized_central <> normalized_eocd
  end

  defp reorder_central_directory!(path) do
    {:ok, parts} = :escript.extract(String.to_charlist(path), [])
    archive = Keyword.fetch!(parts, :archive)
    [{eocd_offset, 4}] = :binary.matches(archive, <<0x50, 0x4B, 0x05, 0x06>>)
    eocd = binary_part(archive, eocd_offset, byte_size(archive) - eocd_offset)

    <<0x06054B50::little-32, _disk::little-16, _central_disk::little-16, _disk_entries::little-16,
      entries::little-16, central_size::little-32, central_offset::little-32,
      _comment_size::little-16, _comment::binary>> = eocd

    local = binary_part(archive, 0, central_offset)
    central = binary_part(archive, central_offset, central_size)
    central_entries = central_directory_entries!(central, [])
    reversed = IO.iodata_to_binary(central_entries)
    normalized_archive = local <> reversed <> eocd

    assert length(central_entries) == entries

    {:ok, prefix} = File.read(path)
    prefix_size = byte_size(prefix) - byte_size(archive)
    File.write!(path, binary_part(prefix, 0, prefix_size) <> normalized_archive)
  end

  defp central_directory_entries!(<<>>, entries), do: entries

  defp central_directory_entries!(
         <<fixed::binary-size(46), rest::binary>>,
         entries
       ) do
    <<0x02014B50::little-32, _::binary-size(24), name_size::little-16, extra_size::little-16,
      comment_size::little-16, _::binary-size(12)>> = fixed

    size = name_size + extra_size + comment_size
    <<fields::binary-size(^size), tail::binary>> = rest
    central_directory_entries!(tail, [fixed <> fields | entries])
  end

  defp escript_entries!(path) do
    {:ok, parts} = :escript.extract(String.to_charlist(path), [])
    {:ok, files} = :zip.extract(Keyword.fetch!(parts, :archive), [:memory])
    Enum.map(files, fn {name, _} -> to_string(name) end)
  end

  defp with_environment(values, function) do
    previous = Map.take(System.get_env(), Map.keys(values))

    try do
      Enum.each(values, fn {key, value} -> System.put_env(key, value) end)
      function.()
    after
      Enum.each(values, fn {key, _} -> System.delete_env(key) end)
      Enum.each(previous, fn {key, value} -> System.put_env(key, value) end)
    end
  end
end
