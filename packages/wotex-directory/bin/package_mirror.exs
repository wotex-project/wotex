defmodule DirectoryPackageMirror do
  @moduledoc false

  @sentinel_paths ~w(
    AGENTS.md CLAUDE.md .claude/local.json .codex/local.json .agents/local.json
    .git/exclusion-sentinel .github/exclusion-sentinel
    docs/tasks/local/exclusion-sentinel.json docs/tasks/local/nested/exclusion-sentinel.json
    docs/tasks/exclusion-sentinel.json docs/plans/exclusion-sentinel.json
    docs/specs/exclusion-sentinel.json docs/provenance/exclusion-sentinel.json
    _build/exclusion-sentinel deps/exclusion-sentinel doc/exclusion-sentinel
    cover/exclusion-sentinel test/exclusion-sentinel bin/exclusion-sentinel
    priv/plts/exclusion-sentinel tmp/exclusion-sentinel
    inputs.etf compiler.exit archive-evidence.json release-evidence.json
    consumer.mix.lock consumer/exclusion-sentinel wotex_directory-0.1.0.tar
  )

  def prepare!(source, root, allowlist) do
    temporary_root!(root)
    directory = Path.join(root, "package-source")
    File.mkdir!(directory)

    inputs =
      for relative <- allowlist,
          path <- input_files!(source, relative),
          into: %{} do
        relative = Path.relative_to(path, source)
        destination = Path.join(directory, relative)
        File.mkdir_p!(Path.dirname(destination))
        File.cp!(path, destination)
        {relative, digest(path)}
      end

    sentinels =
      for path <- @sentinel_paths, into: %{} do
        if Map.has_key?(inputs, path), do: raise("sentinel collides with a public package input")
        bytes = "excluded-package-state:" <> Base.encode16(:crypto.strong_rand_bytes(32))
        destination = Path.join(directory, path)
        File.mkdir_p!(Path.dirname(destination))
        File.write!(destination, bytes)
        {path, bytes}
      end

    mirror = %{directory: directory, inputs: inputs, sentinels: sentinels}
    unchanged!(mirror)
    mirror
  end

  def verify!(mirror, archive, metadata) do
    unchanged!(mirror)

    for path <- Map.keys(mirror.sentinels) do
      if File.exists?(Path.join(archive, path)), do: raise("excluded sentinel path in archive")
    end

    files = regular_files!(archive)
    contents = [metadata | Enum.map(files, &File.read!/1)]

    for bytes <- Map.values(mirror.sentinels) do
      if Enum.any?(contents, &String.contains?(&1, bytes)),
        do: raise("excluded sentinel bytes in archive")
    end

    actual =
      for path <- files,
          into: %{},
          do: {Path.relative_to(path, archive), digest(path)}

    unless actual == mirror.inputs,
      do: raise("archive members differ from intended source bytes")

    %{
      "member_sha256" => actual,
      "excluded_sentinels" =>
        Map.new(mirror.sentinels, fn {path, bytes} ->
          {path, :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)}
        end),
      "sentinels_present_before_and_after_build" => true,
      "member_bytes_match" => true,
      "sentinel_paths_absent" => true,
      "sentinel_bytes_absent" => true
    }
  end

  def evidence!(proof, source_inputs, allowlist) do
    paths =
      Enum.flat_map(allowlist, fn
        "lib" -> Enum.filter(Map.keys(source_inputs), &String.starts_with?(&1, "lib/"))
        path -> [path]
      end)

    unless is_map(proof) and proof["sentinel_build"] == true and
             proof["directory_build_count"] == 1 and proof["member_bytes_match"] == true and
             proof["sentinels_present_before_and_after_build"] == true and
             proof["sentinel_paths_absent"] == true and proof["sentinel_bytes_absent"] == true and
             proof["member_sha256"] == Map.take(source_inputs, paths) and
             is_map(proof["excluded_sentinels"]) and
             Enum.sort(Map.keys(proof["excluded_sentinels"])) == Enum.sort(@sentinel_paths) and
             Enum.all?(Map.values(proof["excluded_sentinels"]), &valid_digest?/1),
           do: raise("fresh complete package-exclusion evidence is required")

    :ok
  end

  defp valid_digest?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)

  defp unchanged!(mirror) do
    files =
      Map.merge(
        mirror.inputs,
        Map.new(mirror.sentinels, fn {path, bytes} ->
          {path, :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)}
        end)
      )

    for {path, hash} <- files do
      target = Path.join(mirror.directory, path)

      unless File.regular?(target) and digest(target) == hash,
        do: raise("build mirror changed")
    end
  end

  defp input_files!(source, relative) do
    if Path.type(relative) != :relative or ".." in Path.split(relative),
      do: raise("unsafe package allowlist path")

    path = Path.join(source, relative)

    case {relative, File.lstat!(path).type} do
      {"lib", :directory} ->
        files = regular_files!(path)

        unless Enum.all?(files, &(Path.extname(&1) == ".ex")),
          do: raise("undeclared non-Elixir library input")

        files

      {_, :regular} ->
        [path]

      _ ->
        raise "non-regular package input"
    end
  end

  defp regular_files!(path) do
    case File.lstat!(path).type do
      :directory -> path |> File.ls!() |> Enum.flat_map(&regular_files!(Path.join(path, &1)))
      :regular -> [path]
      _ -> raise "non-regular package input"
    end
  end

  defp temporary_root!(root) do
    {physical, 0} = System.cmd("pwd", ["-P"], cd: root)
    {temporary, 0} = System.cmd("pwd", ["-P"], cd: System.tmp_dir!())
    physical = String.trim(physical)

    unless String.starts_with?(physical, String.trim(temporary) <> "/") and
             not repository_ancestor?(physical),
           do: raise("package mirror requires a system temporary directory outside repositories")
  end

  defp repository_ancestor?(path) do
    File.exists?(Path.join(path, ".git")) or
      (Path.dirname(path) != path and repository_ancestor?(Path.dirname(path)))
  end

  defp digest(path), do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
end
