defmodule Mix.Tasks.Wotex.Lab.Hosted.Artifact do
  @moduledoc false

  @runner "wotex-hosted-investigation-runner"
  @worker "wotex-lab-hosted-worker"
  @schema "wotex-lab-hosted-artifact/v1"
  @max_artifact_bytes 256 * 1_024 * 1_024
  @max_escript_entries 4_096
  @max_escript_uncompressed_bytes 64 * 1_024 * 1_024
  @zip_epoch 315_532_800
  @escript_apps ~w(
    baml_elixir beamlens castore decimal elixir finch hpax jason logger lua luerl
    mime mint nimble_options nimble_ownership nimble_pool puck recon req
    rustler_precompiled ssl_verify_fun telemetry zoi
  )
  @escript_entries ~w(
    nil_escript.beam
    wotex_lab/ebin/Elixir.Wotex.Lab.Error.beam
    wotex_lab/ebin/Elixir.Wotex.Lab.Metrics.Catalogue.beam
    wotex_lab/ebin/Elixir.Wotex.Lab.Metrics.Query.beam
    wotex_lab/ebin/Elixir.Wotex.Lab.Options.beam
    wotex_lab/ebin/Elixir.Wotex.Lab.Telemetry.beam
    wotex_lab_workbench/ebin/Elixir.WotexLabWorkbench.Investigation.BeamlensSupervisor.beam
    wotex_lab_workbench/ebin/Elixir.WotexLabWorkbench.Investigation.ContextStore.beam
    wotex_lab_workbench/ebin/Elixir.WotexLabWorkbench.Investigation.HostedSkill.beam
    wotex_lab_workbench/ebin/Elixir.WotexLabWorkbench.Investigation.HostedWorker.beam
    wotex_lab_workbench/ebin/Elixir.WotexLabWorkbench.Investigation.OperatorRunner.beam
  )
  @excluded_escript_entries ~w(
    puck/ebin/Elixir.Puck.Baml.beam
    puck/ebin/Elixir.Puck.Baml.PuckSummarize.beam
  )
  @result_prefix "WOTEX_HOSTED_WORKER_RESULT "
  @runner_header ~r/\AWOTEX_HOSTED_RUNNER cleanup=ok outcome=exit status=0 output_bytes=(\d{1,7})\r?\n/
  @build_environment_keys ~w(CARGO_HOME HOME MIX_ARCHIVES MIX_HOME PATH RUSTUP_HOME RUSTUP_TOOLCHAIN)
  @elixir_version "1.20.2"
  @otp_release "29"
  @erts_version "17.0.4"
  @rustc_version "rustc 1.97.1 (8bab26f4f 2026-07-14)"
  @cargo_version "cargo 1.97.1 (c980f4866 2026-06-30)"
  @targets ~w(aarch64-apple-darwin aarch64-unknown-linux-gnu x86_64-unknown-linux-gnu)

  @doc false
  @spec build(Path.t(), Path.t()) :: :ok | no_return()
  def build(workspace, runtime) do
    package = package_root()
    workspace = absent_workspace!(workspace)
    runtime = artifact!(runtime, true)
    stage = private_sibling!(workspace, "build")
    build_root = private_build_root!(package)

    try do
      output = Path.join(stage, "output/bin")
      cargo_target = Path.join(build_root, "cargo")
      mix_build = Path.join(build_root, "mix")
      File.mkdir_p!(output)
      build_environment = build_environment(build_root)
      toolchain = toolchain!(build_environment)

      {precompiled_cache, precompiled_inputs} =
        prepare_precompiled_cache!(
          Path.join(package, "hosts/workbench"),
          build_root,
          toolchain.target
        )

      command!(
        "cargo",
        [
          "build",
          "--offline",
          "--locked",
          "--release",
          "--manifest-path",
          Path.join(package, "priv/conformance/native/Cargo.toml"),
          "--bin",
          @runner,
          "--target-dir",
          cargo_target
        ],
        package,
        build_environment
      )

      runner_source = Path.join([cargo_target, "release", @runner])
      runner = Path.join(output, @runner)
      File.cp!(runner_source, runner)
      File.chmod!(runner, 0o755)

      worker = Path.join(output, @worker)

      try do
        command!(
          "mix",
          ["escript.build"],
          Path.join(package, "hosts/workbench"),
          build_environment(build_root, [
            {"HEX_OFFLINE", "1"},
            {"HTTP_PROXY", "http://127.0.0.1:1"},
            {"HTTPS_PROXY", "http://127.0.0.1:1"},
            {"MIX_ENV", "dev"},
            {"MIX_BUILD_PATH", mix_build},
            {"NO_PROXY", ""},
            {"REBAR_BASE_DIR", Path.join(build_root, "rebar")},
            {"RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH", precompiled_cache},
            {"WOTEX_PATH_DEPS", "1"},
            {"WOTEX_LAB_HOSTED_WORKER_OUTPUT", worker}
          ])
        )
      after
        File.chmod!(precompiled_cache, 0o700)
      end

      normalize_escript!(worker)
      File.chmod!(worker, 0o755)
      runner = artifact!(runner, true)
      worker = artifact!(worker, true)

      manifest = %{
        "build_environment" => "dev",
        "cargo_version" => toolchain.cargo,
        "elixir_version" => toolchain.elixir,
        "schema_version" => @schema,
        "source_revision" => revision!(package, build_environment),
        "target" => toolchain.target,
        "otp_release" => toolchain.otp,
        "precompiled_inputs" => precompiled_inputs,
        "erts_version" => toolchain.erts,
        "rustc_version" => toolchain.rustc,
        "runtime" => %{
          "kind" => "escript",
          "sha256" => runtime.digest,
          "size" => runtime.size
        },
        "outputs" => [
          output("output/bin/" <> @runner, runner),
          output("output/bin/" <> @worker, worker)
        ]
      }

      manifest_path = Path.join(stage, "native-build.json")
      File.write!(manifest_path, Jason.encode!(manifest, pretty: true) <> "\n", [:exclusive])
      File.chmod!(manifest_path, 0o644)
      File.rename!(stage, workspace)

      Mix.shell().info("Hosted investigation artifact completed: #{workspace}")
      Mix.shell().info("Manifest: #{Path.join(workspace, "native-build.json")}")
      :ok
    after
      remove_build_root(build_root, package)
      remove_private(stage, workspace)
    end
  end

  @doc false
  @spec check(Path.t(), Path.t()) :: :ok | no_return()
  def check(workspace, runtime) do
    workspace = existing_workspace!(workspace)
    runtime = artifact!(runtime, true)
    manifest = manifest!(workspace)

    require!(get_in(manifest, ["runtime", "sha256"]) == runtime.digest, "runtime digest changed")
    require!(get_in(manifest, ["runtime", "size"]) == runtime.size, "runtime size changed")

    outputs = Map.new(manifest["outputs"], &{&1["path"], &1})
    runner = verify_output!(workspace, outputs, "output/bin/" <> @runner)
    worker = verify_output!(workspace, outputs, "output/bin/" <> @worker)
    work = private_child!(workspace, "qualify")

    try do
      capability = capability()
      result_capability = capability()
      request_path = Path.join(work, "request.json")

      request = %{
        "schema_version" => "wotex-lab-hosted-investigation/v1",
        "prompt" => "Report whether evidence is available.",
        "current" => nil,
        "baseline" => nil,
        "provider_url" => "http://127.0.0.1:1/api/internal/beamlens/v1",
        "query_url" => "http://127.0.0.1:1/api/internal/hosted-investigation/v1/query",
        "provider_capability" => capability,
        "query_capability" => capability,
        "result_capability" => result_capability,
        "timeout_ms" => 9_000
      }

      File.write!(request_path, Jason.encode!(request), [:exclusive])
      File.chmod!(request_path, 0o600)

      {answer, status} =
        System.cmd(
          runner.path,
          [
            "--wall-ms",
            "10000",
            "--output-bytes",
            "262144",
            "--work-dir",
            work,
            "--temp-dir",
            work,
            "--",
            runtime.path,
            worker.path,
            "--request",
            request_path
          ],
          cd: work,
          env: scrubbed_environment(work),
          stderr_to_stdout: true
        )

      require!(status == 0, "isolated worker did not exit cleanly")
      verify_result!(answer, result_capability)
      Mix.shell().info("Hosted investigation artifact qualified: #{workspace}")
      :ok
    after
      File.rm_rf!(work)
    end
  end

  @doc false
  @spec arguments([String.t()]) :: {Path.t(), Path.t()} | no_return()
  def arguments(args) do
    {options, remaining, invalid} =
      OptionParser.parse(args, strict: [workspace: :string, runtime: :string])

    workspace = options[:workspace]
    runtime = options[:runtime]

    if remaining == [] and invalid == [] and is_binary(workspace) and is_binary(runtime),
      do: {workspace, runtime},
      else: Mix.raise("expected exactly --workspace ABSOLUTE_PATH --runtime ABSOLUTE_PATH")
  end

  defp verify_result!(answer, result_capability) do
    with [header, claimed] <- Regex.run(@runner_header, answer),
         payload <- String.replace_prefix(answer, header, ""),
         {size, ""} <- Integer.parse(claimed),
         true <- size == byte_size(payload),
         marker = @result_prefix <> result_capability <> " ",
         true <- length(:binary.matches(payload, marker)) == 1,
         lines <- :binary.split(payload, "\n", [:global]),
         [<<>>, line | _] <- Enum.reverse(lines),
         line <- String.trim_trailing(line, "\r"),
         true <- String.starts_with?(line, marker),
         encoded <- binary_part(line, byte_size(marker), byte_size(line) - byte_size(marker)),
         {:ok, json} <- Base.url_decode64(encoded, padding: false),
         {:ok, %{"status" => "error", "evidence" => evidence}} <- Jason.decode(json),
         true <- is_list(evidence) do
      :ok
    else
      _ -> Mix.raise("isolated worker returned an invalid result")
    end
  end

  defp manifest!(workspace) do
    path = Path.join(workspace, "native-build.json")

    with {:ok, stat} <- File.lstat(path),
         true <- stat.type == :regular and stat.size in 1..65_536,
         {:ok, bytes} <- File.read(path),
         {:ok, manifest} when is_map(manifest) <- Jason.decode(bytes),
         true <-
           Map.keys(manifest) |> Enum.sort() ==
             ~w(build_environment cargo_version elixir_version erts_version otp_release outputs precompiled_inputs runtime rustc_version schema_version source_revision target),
         @schema <- manifest["schema_version"],
         "dev" <- manifest["build_environment"],
         true <- version?(manifest["cargo_version"]),
         true <- version?(manifest["elixir_version"]),
         true <- version?(manifest["erts_version"]),
         true <- version?(manifest["otp_release"]),
         true <- version?(manifest["rustc_version"]),
         true <- version?(manifest["target"]),
         true <- revision?(manifest["source_revision"]),
         true <- precompiled_inputs?(manifest["precompiled_inputs"]),
         outputs when is_list(outputs) and length(outputs) == 2 <- manifest["outputs"],
         %{"kind" => "escript", "sha256" => digest, "size" => size} = runtime <-
           manifest["runtime"],
         true <- map_size(runtime) == 3 and digest?(digest) and positive_size?(size) do
      manifest
    else
      _ -> Mix.raise("hosted investigation manifest is invalid")
    end
  end

  defp verify_output!(workspace, outputs, relative) do
    expected = outputs[relative]

    require!(
      is_map(expected) and map_size(expected) == 5 and expected["kind"] == "file" and
        expected["mode"] == 493 and digest?(expected["sha256"]) and
        positive_size?(expected["size"]),
      "hosted investigation output declaration is invalid"
    )

    artifact = artifact!(Path.join(workspace, relative), true)
    require!(artifact.digest == expected["sha256"], "hosted investigation output digest changed")
    require!(artifact.size == expected["size"], "hosted investigation output size changed")
    artifact
  end

  defp output(relative, artifact) do
    %{
      "path" => relative,
      "kind" => "file",
      "mode" => 493,
      "size" => artifact.size,
      "sha256" => artifact.digest
    }
  end

  defp artifact!(path, executable?) do
    require!(is_binary(path) and Path.type(path) == :absolute, "artifact path must be absolute")

    with {:ok, before} <- File.lstat(path),
         true <- before.type == :regular and before.size in 1..@max_artifact_bytes,
         true <- not executable? or Bitwise.band(before.mode, 0o111) != 0,
         true <- Bitwise.band(before.mode, 0o022) == 0,
         {:ok, digest} <- digest(path),
         {:ok, after_stat} <- File.lstat(path),
         true <- stable?(before, after_stat) do
      %{path: path, size: before.size, digest: digest}
    else
      _ -> Mix.raise("artifact is invalid: #{inspect(path)}")
    end
  end

  defp digest(path) do
    with {:ok, file} <- File.open(path, [:read, :binary]) do
      try do
        digest_stream(file, :crypto.hash_init(:sha256), 0)
      after
        File.close(file)
      end
    end
  end

  defp digest_stream(file, context, size) do
    case IO.binread(file, 64 * 1_024) do
      :eof ->
        encoded =
          context
          |> :crypto.hash_final()
          |> Base.encode16(case: :lower)

        {:ok, "sha256:" <> encoded}

      bytes when is_binary(bytes) and size + byte_size(bytes) <= @max_artifact_bytes ->
        digest_stream(file, :crypto.hash_update(context, bytes), size + byte_size(bytes))

      _ ->
        {:error, :artifact_too_large}
    end
  end

  defp command!(command, args, cd, env) do
    {output, status} =
      System.cmd(command, args,
        cd: cd,
        env: env,
        stderr_to_stdout: true
      )

    cond do
      status != 0 ->
        detail =
          binary_part(output, max(byte_size(output) - 8_192, 0), min(byte_size(output), 8_192))

        Mix.raise("#{command} failed while building the hosted investigation artifact:\n#{detail}")

      byte_size(output) > 1_048_576 ->
        Mix.raise("#{command} produced excessive build output")

      true ->
        :ok
    end
  end

  defp prepare_precompiled_cache!(workbench, stage, target) do
    checksums =
      workbench
      |> Path.join("deps/*/checksum-*.exs")
      |> Path.wildcard()
      |> Enum.sort()

    require!(checksums != [], "precompiled dependency receipts are unavailable")
    source_cache = source_precompiled_cache()
    private_cache = Path.join(stage, "rustler-cache")
    File.mkdir!(private_cache)
    File.chmod!(private_cache, 0o700)

    receipts =
      Enum.map(checksums, fn checksum_path ->
        dependency =
          checksum_path
          |> Path.dirname()
          |> Path.basename()

        bytes = File.read!(checksum_path)
        escaped = Regex.escape(target)

        matches =
          Regex.scan(
            ~r/"([^"\n]*#{escaped}\.so\.tar\.gz)"\s*=>\s*"(sha256:[0-9a-f]{64})"/,
            bytes,
            capture: :all_but_first
          )

        require!(length(matches) == 1, "precompiled dependency target receipt is ambiguous")
        [[filename, expected]] = matches
        source = Path.join(source_cache, filename)
        artifact = artifact!(source, false)
        require!(artifact.digest == expected, "precompiled dependency digest changed")
        destination = Path.join(private_cache, filename)
        File.cp!(source, destination)
        File.chmod!(destination, 0o400)

        %{
          "dependency" => dependency,
          "filename" => filename,
          "sha256" => expected,
          "size" => artifact.size
        }
      end)

    File.chmod!(private_cache, 0o500)
    {private_cache, receipts}
  rescue
    _ -> Mix.raise("verified precompiled dependency cache is unavailable")
  end

  defp source_precompiled_cache do
    case System.get_env("RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH") do
      path when is_binary(path) and path != "" -> path
      _ -> :filename.basedir(:user_cache, "rustler_precompiled/precompiled_nifs") |> to_string()
    end
  end

  @doc false
  @spec normalize_escript!(Path.t()) :: :ok | no_return()
  def normalize_escript!(path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, parts} <- :escript.extract(String.to_charlist(path), []),
         archive when is_binary(archive) <- Keyword.get(parts, :archive),
         prefix_size when prefix_size >= 0 <- byte_size(bytes) - byte_size(archive),
         prefix <- binary_part(bytes, 0, prefix_size),
         normalized <- normalize_zip!(archive),
         {:ok, files} <- :zip.extract(normalized, [:memory]),
         selected <- select_escript_entries!(files),
         {:ok, {_, selected_archive}} <-
           :zip.create(~c"wotex-lab-hosted-worker.zip", selected, [
             :memory,
             {:uncompress, :all},
             {:extra, []}
           ]),
         selected_archive <- normalize_zip!(selected_archive),
         {:ok, _} <- :zip.extract(selected_archive, [:memory]),
         :ok <- File.write(path, prefix <> selected_archive, [:binary]) do
      :ok
    else
      _ -> Mix.raise("hosted worker Escript could not be normalized")
    end
  end

  defp select_escript_entries!(files) do
    selected =
      files
      |> Enum.filter(fn {name, bytes} ->
        is_list(name) and is_binary(bytes) and selected_escript_entry?(to_string(name))
      end)
      |> Enum.sort_by(fn {name, _} -> name end)

    selected_names = MapSet.new(selected, fn {name, _} -> to_string(name) end)

    require!(
      MapSet.subset?(MapSet.new(@escript_entries), selected_names),
      "hosted worker Escript is missing a required entry"
    )

    require!(
      Enum.sum(Enum.map(selected, fn {_, bytes} -> byte_size(bytes) end)) <=
        @max_escript_uncompressed_bytes,
      "hosted worker Escript is too large"
    )

    require!(selected != [], "hosted worker Escript is empty")
    selected
  end

  defp selected_escript_entry?(name) do
    name not in @excluded_escript_entries and
      (name in @escript_entries or
         case String.split(name, "/", parts: 2) do
           [app, _] -> app in @escript_apps
           _ -> false
         end)
  end

  defp normalize_zip!(archive) do
    {eocd_offset, eocd} = zip_eocd!(archive)

    <<0x06054B50::little-32, disk::little-16, central_disk::little-16, disk_entries::little-16,
      entries::little-16, central_size::little-32, central_offset::little-32,
      comment_size::little-16, comment::binary>> = eocd

    require!(disk == 0 and central_disk == 0, "hosted worker ZIP spans disks")
    require!(disk_entries == entries, "hosted worker ZIP entry counts differ")
    require!(entries in 1..@max_escript_entries, "hosted worker ZIP entry count is invalid")
    require!(comment_size == 0 and comment == <<>>, "hosted worker ZIP comment is invalid")

    require!(
      central_offset + central_size == eocd_offset,
      "hosted worker ZIP directory is invalid"
    )

    local = binary_part(archive, 0, central_offset)
    central = binary_part(archive, central_offset, central_size)
    {normalized_local, local_entries} = normalize_local_entries!(local, 0, [], 0)
    {normalized_central, central_entries} = normalize_central_entries!(central, [], entries)
    local_paths = Enum.map(local_entries, &elem(&1, 0))

    require!(
      length(Enum.uniq(local_paths)) == length(local_paths),
      "hosted worker ZIP contains duplicate paths"
    )

    require!(
      Enum.reverse(local_entries) == Enum.reverse(central_entries),
      "hosted worker ZIP directories disagree"
    )

    normalized_local <> normalized_central <> eocd
  end

  defp zip_eocd!(archive) do
    matches = :binary.matches(archive, <<0x50, 0x4B, 0x05, 0x06>>)
    require!(matches != [], "hosted worker ZIP has no end record")
    {offset, 4} = List.last(matches)
    eocd = binary_part(archive, offset, byte_size(archive) - offset)

    require!(byte_size(eocd) >= 22, "hosted worker ZIP end record is truncated")
    {offset, eocd}
  end

  defp normalize_local_entries!(<<>>, _, entries, _),
    do: {<<>>, entries}

  defp normalize_local_entries!(bytes, offset, entries, uncompressed) do
    with <<fixed::binary-size(30), rest::binary>> <- bytes,
         <<0x04034B50::little-32, version::little-16, flags::little-16, compression::little-16,
           _::little-16, _::little-16, crc::little-32, compressed_size::little-32,
           uncompressed_size::little-32, name_size::little-16, extra_size::little-16>> <- fixed,
         true <- Bitwise.band(flags, 0x0009) == 0,
         true <- compression in [0, 8],
         true <- compressed_size < 0xFFFFFFFF and uncompressed_size < 0xFFFFFFFF,
         true <- name_size in 1..1_024 and extra_size <= 1_024,
         <<name::binary-size(^name_size), extra::binary-size(^extra_size), tail::binary>> <- rest,
         true <- safe_zip_name?(name),
         true <- byte_size(tail) >= compressed_size,
         <<payload::binary-size(^compressed_size), remaining::binary>> <- tail,
         total = uncompressed + uncompressed_size,
         true <- total <= @max_escript_uncompressed_bytes do
      normalized_extra = normalize_zip_extra!(extra)

      header =
        <<0x04034B50::little-32, version::little-16, flags::little-16, compression::little-16,
          0::little-16, 0x0021::little-16, crc::little-32, compressed_size::little-32,
          uncompressed_size::little-32, name_size::little-16, extra_size::little-16, name::binary,
          normalized_extra::binary, payload::binary>>

      entry = {name, offset, flags, compression, crc, compressed_size, uncompressed_size}
      next_offset = offset + byte_size(header)

      {normalized_remaining, entries} =
        normalize_local_entries!(remaining, next_offset, [entry | entries], total)

      {header <> normalized_remaining, entries}
    else
      _ -> Mix.raise("hosted worker ZIP local entry is invalid")
    end
  end

  defp normalize_central_entries!(<<>>, entries, expected) do
    require!(length(entries) == expected, "hosted worker ZIP directory count is invalid")
    {<<>>, entries}
  end

  defp normalize_central_entries!(bytes, entries, expected) do
    with <<0x02014B50::little-32, made_by::little-16, version::little-16, flags::little-16,
           compression::little-16, _::little-16, _::little-16, crc::little-32,
           compressed_size::little-32, uncompressed_size::little-32, name_size::little-16,
           extra_size::little-16, comment_size::little-16, disk::little-16,
           internal_attributes::little-16, external_attributes::little-32, local_offset::little-32,
           rest::binary>> <- bytes,
         true <- Bitwise.band(flags, 0x0009) == 0,
         true <- compression in [0, 8],
         true <- compressed_size < 0xFFFFFFFF and uncompressed_size < 0xFFFFFFFF,
         true <- disk == 0 and comment_size == 0,
         true <- name_size in 1..1_024 and extra_size <= 1_024,
         <<name::binary-size(^name_size), extra::binary-size(^extra_size),
           _::binary-size(^comment_size), remaining::binary>> <- rest,
         true <- safe_zip_name?(name) do
      normalized_extra = normalize_zip_extra!(extra)

      header =
        <<0x02014B50::little-32, made_by::little-16, version::little-16, flags::little-16,
          compression::little-16, 0::little-16, 0x0021::little-16, crc::little-32,
          compressed_size::little-32, uncompressed_size::little-32, name_size::little-16,
          extra_size::little-16, 0::little-16, disk::little-16, internal_attributes::little-16,
          external_attributes::little-32, local_offset::little-32, name::binary,
          normalized_extra::binary>>

      {normalized_remaining, entries} =
        normalize_central_entries!(
          remaining,
          [
            {name, local_offset, flags, compression, crc, compressed_size, uncompressed_size}
            | entries
          ],
          expected
        )

      {header <> normalized_remaining, entries}
    else
      _ -> Mix.raise("hosted worker ZIP directory entry is invalid")
    end
  end

  defp normalize_zip_extra!(<<>>), do: <<>>

  defp normalize_zip_extra!(<<id::little-16, size::little-16, rest::binary>>) do
    with true <- size <= byte_size(rest),
         <<value::binary-size(^size), remaining::binary>> <- rest do
      normalized =
        case id do
          0x5455 -> normalize_extended_time!(value)
          0x7875 -> normalize_unix_ownership!(value)
          _ -> Mix.raise("hosted worker ZIP contains an unknown extra field")
        end

      <<id::little-16, size::little-16, normalized::binary>> <>
        normalize_zip_extra!(remaining)
    else
      _ -> Mix.raise("hosted worker ZIP extra field is invalid")
    end
  end

  defp normalize_zip_extra!(_), do: Mix.raise("hosted worker ZIP extra field is truncated")

  defp normalize_extended_time!(<<flags, timestamps::binary>>) do
    count = Enum.count(0..2, &(Bitwise.band(flags, Bitwise.bsl(1, &1)) != 0))
    require!(Bitwise.band(flags, 0xF8) == 0, "hosted worker ZIP timestamp flags are invalid")
    require!(byte_size(timestamps) == count * 4, "hosted worker ZIP timestamps are invalid")

    <<flags>> <>
      :binary.copy(<<@zip_epoch::little-32>>, count)
  end

  defp normalize_extended_time!(_), do: Mix.raise("hosted worker ZIP timestamps are invalid")

  defp normalize_unix_ownership!(
         <<1, uid_size, uid::binary-size(uid_size), gid_size, gid::binary-size(gid_size)>>
       )
       when uid_size in 1..8 and gid_size in 1..8 do
    <<1, uid_size, :binary.copy(<<0>>, byte_size(uid))::binary, gid_size,
      :binary.copy(<<0>>, byte_size(gid))::binary>>
  end

  defp normalize_unix_ownership!(_),
    do: Mix.raise("hosted worker ZIP ownership field is invalid")

  defp safe_zip_name?(name) do
    String.valid?(name) and not String.contains?(name, [<<0>>, "\\"]) and
      Path.type(name) == :relative and
      Enum.all?(Path.split(name), &(&1 not in ["", ".", ".."]))
  end

  defp rust_host!(environment) do
    {output, status} =
      System.cmd("rustc", ["-vV"], env: environment, stderr_to_stdout: true)

    case {status, Regex.run(~r/^host: ([a-zA-Z0-9_.-]+)$/m, output)} do
      {0, [_, target]} -> target
      _ -> Mix.raise("rustc did not report its host target")
    end
  end

  defp tool_version!(command, environment) do
    {output, status} =
      System.cmd(command, ["--version"], env: environment, stderr_to_stdout: true)

    lines =
      output
      |> String.trim()
      |> String.split("\n", parts: 2)

    case {status, lines} do
      {0, [version]} when byte_size(version) in 1..128 -> version
      _ -> Mix.raise("#{command} did not report a valid version")
    end
  end

  defp toolchain!(environment) do
    actual = %{
      cargo: tool_version!("cargo", environment),
      elixir: System.version(),
      erts: to_string(:erlang.system_info(:version)),
      otp: to_string(:erlang.system_info(:otp_release)),
      rustc: tool_version!("rustc", environment),
      target: rust_host!(environment)
    }

    expected = %{
      cargo: @cargo_version,
      elixir: @elixir_version,
      erts: @erts_version,
      otp: @otp_release,
      rustc: @rustc_version
    }

    require!(
      Map.take(actual, Map.keys(expected)) == expected,
      "hosted toolchain does not match repository pins"
    )

    require!(actual.target in @targets, "hosted target is not admitted")
    actual
  end

  defp revision!(package, environment) do
    {revision, status} =
      System.cmd("git", ["rev-parse", "--verify", "HEAD"],
        cd: package,
        env: environment,
        stderr_to_stdout: true
      )

    revision = String.trim(revision)

    require!(
      status == 0 and Regex.match?(~r/\A[0-9a-f]{40,64}\z/, revision),
      "revision unavailable"
    )

    revision
  end

  defp absent_workspace!(path) do
    require!(is_binary(path) and Path.type(path) == :absolute, "workspace must be absolute")
    parent = Path.dirname(path)

    require!(
      match?({:ok, %File.Stat{type: :directory}}, File.lstat(parent)),
      "workspace parent is invalid"
    )

    require!(match?({:error, :enoent}, File.lstat(path)), "workspace already exists")
    path
  end

  defp existing_workspace!(path) do
    require!(is_binary(path) and Path.type(path) == :absolute, "workspace must be absolute")
    require!(match?({:ok, %File.Stat{type: :directory}}, File.lstat(path)), "workspace is invalid")
    path
  end

  defp private_sibling!(workspace, purpose) do
    parent = Path.dirname(workspace)
    name = ".wotex-hosted-#{purpose}-" <> random_name()
    path = Path.join(parent, name)
    File.mkdir!(path)
    File.chmod!(path, 0o700)
    path
  end

  defp private_child!(workspace, purpose) do
    path = Path.join(workspace, ".wotex-hosted-#{purpose}-" <> random_name())
    File.mkdir!(path)
    File.chmod!(path, 0o700)
    path
  end

  defp private_build_root!(package) do
    root = Path.expand("../..", package)
    path = Path.join(root, ".wotex-hosted-build-" <> random_name())
    File.mkdir!(path)
    File.chmod!(path, 0o700)
    path
  end

  defp remove_build_root(path, package) do
    root = Path.expand("../..", package)

    if Path.dirname(path) == root and
         String.starts_with?(Path.basename(path), ".wotex-hosted-build-") do
      File.rm_rf!(path)
    end
  end

  defp remove_private(stage, workspace) do
    if Path.dirname(stage) == Path.dirname(workspace) and
         String.starts_with?(Path.basename(stage), ".wotex-hosted-build-") do
      File.rm_rf!(stage)
    end
  end

  defp scrubbed_environment(directory) do
    System.get_env()
    |> Map.new(fn {key, _} -> {key, nil} end)
    |> Map.merge(%{
      "HOME" => directory,
      "TMPDIR" => directory,
      "LANG" => "C.UTF-8",
      "LC_ALL" => "C.UTF-8"
    })
    |> Enum.sort()
  end

  defp build_environment(directory, extra \\ []) do
    current = System.get_env()

    current
    |> Map.new(fn {key, _} -> {key, nil} end)
    |> Map.merge(Map.take(current, @build_environment_keys))
    |> Map.merge(%{"LANG" => "C.UTF-8", "LC_ALL" => "C.UTF-8", "TMPDIR" => directory})
    |> Map.merge(Map.new(extra))
    |> Enum.sort()
  end

  defp stable?(left, right),
    do:
      left.type == right.type and left.size == right.size and left.inode == right.inode and
        left.major_device == right.major_device and left.minor_device == right.minor_device and
        left.mode == right.mode and left.mtime == right.mtime and left.ctime == right.ctime

  defp package_root, do: Path.expand("../../..", __DIR__)
  defp capability, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  defp random_name, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  defp digest?(value), do: is_binary(value) and Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, value)
  defp positive_size?(value), do: is_integer(value) and value in 1..@max_artifact_bytes
  defp revision?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{40,64}\z/, value)
  defp version?(value), do: is_binary(value) and byte_size(value) in 1..128

  defp precompiled_inputs?(inputs) when is_list(inputs) and length(inputs) in 1..16 do
    valid? =
      Enum.all?(inputs, fn input ->
        is_map(input) and map_size(input) == 4 and
          Map.keys(input) |> Enum.sort() == ~w(dependency filename sha256 size) and
          version?(input["dependency"]) and version?(input["filename"]) and
          digest?(input["sha256"]) and positive_size?(input["size"])
      end)

    valid? and Enum.uniq_by(inputs, & &1["dependency"]) == inputs and
      Enum.uniq_by(inputs, & &1["filename"]) == inputs
  end

  defp precompiled_inputs?(_), do: false

  defp require!(true, _), do: :ok
  defp require!(false, message), do: Mix.raise(message)
end

defmodule Mix.Tasks.Wotex.Lab.Hosted.Build do
  @shortdoc "Builds the isolated hosted-investigation artifact"
  @moduledoc "Builds the target-qualified hosted-investigation executables explicitly."

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {workspace, runtime} = Mix.Tasks.Wotex.Lab.Hosted.Artifact.arguments(args)
    Mix.Tasks.Wotex.Lab.Hosted.Artifact.build(workspace, runtime)
  end
end

defmodule Mix.Tasks.Wotex.Lab.Hosted.Check do
  @shortdoc "Qualifies an isolated hosted-investigation artifact"
  @moduledoc "Verifies and executes one bounded hosted-investigation artifact check."

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {workspace, runtime} = Mix.Tasks.Wotex.Lab.Hosted.Artifact.arguments(args)
    Mix.Tasks.Wotex.Lab.Hosted.Artifact.check(workspace, runtime)
  end
end
