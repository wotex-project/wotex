Code.require_file("child_environment.exs", __DIR__)

defmodule Wotex.Lab.Check.ArchiveRepository do
  @moduledoc false

  alias Wotex.Lab.Check.ChildEnvironment

  @type archive :: %{
          name: String.t(),
          version: String.t(),
          path: Path.t(),
          origin: :built | :hex_cache
        }

  @spec build_archives!(Path.t(), [{atom(), String.t()}], Path.t()) :: [archive()]
  def build_archives!(root, packages, tarballs) do
    Enum.map(packages, fn {app, directory} ->
      dir = Path.expand("../#{directory}", root)
      File.dir?(dir) || abort("missing sibling package for #{app} at ../#{directory}")
      env = [{"WOTEX_PATH_DEPS", nil}, {"MIX_ENV", "prod"}]

      {version, 0} =
        System.cmd(
          "mix",
          [
            "run",
            "--no-start",
            "--no-deps-check",
            "--no-compile",
            "-e",
            "IO.write(Mix.Project.config()[:version])"
          ],
          cd: dir,
          env: env,
          stderr_to_stdout: true
        )

      version =
        version
        |> String.split("\n")
        |> List.last()
        |> String.trim()

      Regex.match?(~r/\A\d+\.\d+\.\d+\z/, version) ||
        abort("cannot read #{app} version: #{version}")

      output = Path.join(tarballs, "#{app}-#{version}.tar")

      {log, status} =
        System.cmd("mix", ["hex.build", "--output", output],
          cd: dir,
          env: env,
          stderr_to_stdout: true
        )

      status == 0 || abort("hex.build failed for #{app}:\n#{log}")
      File.regular?(output) || abort("hex.build produced no archive for #{app}")
      %{name: Atom.to_string(app), version: version, path: output, origin: :built}
    end)
  end

  # Public dependencies are admitted only at exact locked versions from the
  # local Hex cache. No package is fetched from the network by this step.
  @spec copy_public_archives!([Path.t()], Path.t(), MapSet.t(String.t())) :: [archive()]
  def copy_public_archives!(lock_paths, tarballs, excluded_names \\ MapSet.new()) do
    cache = Path.join([hex_home(), "packages", "hexpm"])

    lock_paths
    |> Enum.flat_map(fn path ->
      path
      |> read_lock!()
      |> Enum.flat_map(fn
        {name, entry} when is_tuple(entry) and elem(entry, 0) == :hex ->
          copy_locked_archive!(cache, tarballs, excluded_names, name, elem(entry, 2))

        _ ->
          []
      end)
    end)
    |> Enum.uniq_by(&{&1.name, &1.version})
  end

  @spec read_lock!(Path.t()) :: map()
  def read_lock!(path) do
    {{lock, _}, _} = Code.with_diagnostics(fn -> Code.eval_file(path) end)
    lock
  end

  @spec build_registry!(Path.t(), Path.t()) :: Path.t()
  def build_registry!(work, tarballs) do
    public = Path.join(work, "public")
    key = Path.join(work, "registry_key.pem")
    private = :public_key.generate_key({:rsa, 2048, 65_537})

    File.write!(
      key,
      :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, private)])
    )

    File.mkdir_p!(Path.join(public, "tarballs"))

    tarballs
    |> File.ls!()
    |> Enum.each(&File.cp!(Path.join(tarballs, &1), Path.join([public, "tarballs", &1])))

    {log, status} =
      System.cmd("mix", ["hex.registry", "build", public, "--name=hexpm", "--private-key=#{key}"],
        env: ChildEnvironment.scrubbed(),
        stderr_to_stdout: true
      )

    status == 0 || abort("registry build failed:\n#{log}")
    public
  end

  @spec serve!(Path.t(), Path.t()) :: {pid(), :inet.port_number()}
  def serve!(work, public) do
    {:ok, _} = Application.ensure_all_started(:inets)

    {:ok, httpd} =
      :inets.start(:httpd,
        port: 0,
        bind_address: {127, 0, 0, 1},
        server_name: ~c"wotex-archive-registry",
        server_root: String.to_charlist(work),
        document_root: String.to_charlist(public),
        mime_types: [{~c"tar", ~c"application/octet-stream"}]
      )

    port =
      httpd
      |> :httpd.info()
      |> Keyword.fetch!(:port)

    {httpd, port}
  end

  # Every executable on the current PATH except Git is linked into one private
  # directory. Dependency resolution, compilation and execution all use it.
  @spec restricted_path!(Path.t()) :: Path.t()
  def restricted_path!(work) do
    bin = Path.join(work, "bin")
    File.mkdir_p!(bin)

    System.get_env("PATH", "")
    |> String.split(":", trim: true)
    |> Enum.filter(&(File.dir?(&1) and not Regex.match?(~r{/erts-\d}, &1)))
    |> Enum.each(fn dir ->
      dir
      |> File.ls!()
      |> Enum.reject(&(&1 == "git" or String.starts_with?(&1, "git-")))
      |> Enum.each(fn name ->
        source = Path.join(dir, name)
        target = Path.join(bin, name)

        if executable?(source) and not File.exists?(target) do
          File.ln_s!(source, target)
        end
      end)
    end)

    File.exists?(Path.join(bin, "git")) && abort("git leaked into the restricted PATH")
    bin
  end

  @spec environment(Path.t(), :inet.port_number(), Path.t(), String.t()) ::
          [{String.t(), String.t() | nil}]
  def environment(work, port, bin, mix_env \\ "prod") do
    [
      {"PATH", bin},
      {"ERL_ROOTDIR", List.to_string(:code.root_dir())},
      {"HEX_HOME", Path.join(work, "hex_home")},
      {"HEX_MIRROR", "http://127.0.0.1:#{port}"},
      {"HEX_UNSAFE_REGISTRY", "1"},
      {"HEX_OFFLINE", nil},
      {"WOTEX_PATH_DEPS", nil},
      {"MIX_ENV", mix_env}
    ]
  end

  @spec run!(
          Path.t(),
          [{String.t(), String.t() | nil}],
          [String.t()],
          String.t(),
          non_neg_integer()
        ) :: String.t()
  def run!(directory, env, args, label, deadline_ms) do
    task =
      Task.async(fn ->
        System.cmd("mix", args, cd: directory, env: env, stderr_to_stdout: true)
      end)

    case Task.yield(task, deadline_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, 0}} -> output
      {:ok, {output, status}} -> abort("#{label} failed (#{status}):\n#{output}")
      nil -> abort("#{label} exceeded #{deadline_ms} ms")
    end
  end

  @spec revision(Path.t()) :: String.t()
  def revision(root) do
    result =
      System.cmd("git", ["rev-parse", "HEAD"],
        cd: root,
        env: ChildEnvironment.scrubbed(),
        stderr_to_stdout: true
      )

    case result do
      {sha, 0} -> String.trim(sha)
      _ -> "unknown"
    end
  end

  defp copy_locked_archive!(cache, tarballs, excluded_names, name, version) do
    if MapSet.member?(excluded_names, Atom.to_string(name)) do
      []
    else
      file = "#{name}-#{version}.tar"
      source = Path.join(cache, file)
      File.regular?(source) || abort("locked archive is absent from the local Hex cache: #{file}")
      target = Path.join(tarballs, file)
      File.cp!(source, target)
      [%{name: Atom.to_string(name), version: version, path: target, origin: :hex_cache}]
    end
  end

  defp hex_home, do: System.get_env("HEX_HOME") || Path.join(System.user_home!(), ".hex")

  defp executable?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, mode: mode}} -> Bitwise.band(mode, 0o111) != 0
      {:ok, %File.Stat{type: :symlink}} -> File.regular?(path)
      _ -> false
    end
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end
