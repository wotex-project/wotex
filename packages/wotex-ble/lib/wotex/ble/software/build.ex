defmodule Wotex.BLE.Software.Build do
  @moduledoc """
  Builds the explicit BlueZ virtual-controller software fixture in a workspace.

  `run/1` is invoked by `mix wotex.software.build --workspace ABSOLUTE_PATH`
  from `packages/wotex-ble` in a repository checkout. It requires `docker` and
  `cc` on the caller's `PATH`, records both executable digests and hashes all
  fixture and package inputs before workspace mutation. BlueZ, Hex and Rebar3 source archives arrive
  over verified HTTPS and must match their pins.

  Three Linux arm64 images are built in order through the packaged command
  guardian, each within ten minutes: the Debian system and QEMU layer, the pinned
  BlueZ and virtual HCI module layer, and the public layer that compiles all
  three packages in both BEAM lanes and runs `mix wotex.native.build`. Images
  receive tags owned by the workspace path. The public image is exported to
  `rootfs.tar` and converted to the 6 GiB `rootfs.raw` guest disk.

  `software-manifest.json` binds inputs, tools, downloads, image identities,
  guest build evidence, the guest native build manifest, logs and artifact
  digests. A matching workspace is verified read-only; a failed build keeps its
  lock and logs. Build completion establishes fixture identity only; the
  software run task records execution evidence.
  """

  alias Wotex.BLE.Native.{Source, Workspace}
  alias Wotex.BLE.Software.{Fixture, Operations}

  @manifest "software-manifest.json"
  @lock ".wotex-ble-software.lock"
  @maximum_manifest 4_194_304
  @downloads [
    {"bluez.tar.gz",
     "https://codeload.github.com/bluez/bluez/tar.gz/2123ab772fbe97d1369fc9e179ea87c3469cf98f",
     "53a95c3dc9897f617b8bae0121d3f4c55c28a757bd48546c707bd2bbac45af0a"},
    {"hex-source.tar.gz", "https://codeload.github.com/hexpm/hex/tar.gz/refs/tags/v2.5.1",
     "bdd6ef2015aa6e50a1c21212e098e8cbe7317da65f067955d154d890532742ae"},
    {"rebar-source.tar.gz", "https://codeload.github.com/erlang/rebar3/tar.gz/refs/tags/3.27.0",
     "985cae6e957334cfa549190b9f5efb9185c184a18fc181c87b8dde096ba79f38"}
  ]
  @environment ~w(HOME DOCKER_CONFIG DOCKER_CONTEXT DOCKER_HOST)
  @layers [:system, :bluez, :public]
  @layer_steps %{
    system: {:image_system, :inspect_system, :verify_system},
    bluez: {:image_bluez, :inspect_bluez, :verify_bluez},
    public: {:image_public, :inspect_public, :verify_public}
  }

  @typedoc "A verified software workspace and whether any build step ran."
  @type result :: %{manifest: map(), reused: boolean()}

  @doc "Validates the exact task argument vector before any build I/O."
  @spec arguments(term()) :: {:ok, String.t()} | {:error, :invalid_native_build_arguments}
  defdelegate arguments(args), to: Workspace

  @doc "Builds or read-only verifies one software fixture workspace."
  @spec run(term()) :: {:ok, result()} | {:error, term()}
  def run(workspace), do: run(workspace, File.cwd!(), Operations)

  @doc false
  @spec run(term(), term(), module()) :: {:ok, result()} | {:error, term()}
  def run(workspace, root, operations)
      when is_binary(workspace) and is_binary(root) and is_atom(operations) do
    with {:ok, ^workspace} <- arguments(["--workspace", workspace]),
         {:ok, tools} <- tools(operations),
         {:ok, inputs} <- Fixture.inputs(root) do
      identity = identity(workspace, tools, inputs)

      case state(workspace) do
        :empty -> build(workspace, root, identity, operations)
        {:ok, manifest} -> verify(workspace, identity, manifest, operations)
        error -> error
      end
    end
  end

  def run(_, _, _), do: {:error, :invalid_build_workspace}

  @doc "Reads and verifies a completed workspace for an explicit software run."
  @spec verified(term(), term(), module()) :: {:ok, map()} | {:error, term()}
  def verified(workspace, root, operations)
      when is_binary(workspace) and is_binary(root) and is_atom(operations) do
    with {:ok, ^workspace} <- arguments(["--workspace", workspace]),
         {:ok, tools} <- tools(operations),
         {:ok, inputs} <- Fixture.inputs(root),
         {:ok, manifest} <- completed(state(workspace)),
         {:ok, %{manifest: manifest}} <-
           verify(workspace, identity(workspace, tools, inputs), manifest, operations) do
      {:ok, manifest}
    end
  end

  def verified(_, _, _), do: {:error, :invalid_build_workspace}

  defp completed(:empty), do: {:error, :software_build_required}
  defp completed(state), do: state

  @doc false
  @spec environment(map()) :: [{String.t(), String.t()}]
  def environment(tools) do
    path =
      [Path.dirname(tools["docker"]["path"]), "/usr/local/bin", "/usr/bin", "/bin"]
      |> Enum.uniq()
      |> Enum.join(":")

    inherited =
      for name <- @environment, value = System.get_env(name), is_binary(value), do: {name, value}

    [{"PATH", path}, {"LC_ALL", "C"} | inherited]
  end

  @doc false
  @spec tag(String.t(), atom()) :: String.t()
  def tag(workspace, layer) do
    digest = Base.encode16(:crypto.hash(:sha256, workspace), case: :lower)
    token = binary_part(digest, 0, 16)
    "wotex-ble-software:#{token}-#{layer}"
  end

  @doc false
  @spec docker(map(), module(), atom(), [String.t()], pos_integer()) ::
          {:ok, binary()} | {:error, term()}
  def docker(context, operations, id, args, timeout) do
    step = %{
      id: id,
      executable: context.tools["docker"]["path"],
      args: args,
      cwd: context.workspace,
      env: environment(context.tools),
      timeout_ms: timeout,
      output_bytes: 16_777_216,
      cleanup_ms: 5000
    }

    {output, status, code} =
      case operations.command(Path.join(context.workspace, "bin/build-command"), step) do
        {:ok, details} -> {details.output, details.exit_status, nil}
        {:error, code, details} -> {details.output, details.exit_status, code}
      end

    log = Path.join(Map.get(context, :logs, Path.join(context.workspace, "logs")), "#{id}.log")

    case File.write(log, output) do
      :ok when is_nil(code) -> {:ok, output}
      :ok -> {:error, {:software_command_failed, id, code, status}}
      _ -> {:error, :software_build_filesystem}
    end
  end

  @doc false
  @spec image(map(), module(), atom(), String.t()) ::
          {:ok, String.t()}
          | {:error,
             :invalid_software_image
             | {:software_command_failed, atom(), atom(), integer() | nil}
             | :software_build_filesystem}
  def image(context, operations, id, reference) do
    with {:ok, output} <- docker(context, operations, id, ["image", "inspect", reference], 60_000),
         {:ok, [%{"Id" => identifier, "Architecture" => "arm64", "Os" => "linux"}]} <-
           Jason.decode(output),
         true <- Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, identifier) do
      {:ok, identifier}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_software_image}
    end
  end

  defp tools(operations) do
    Enum.reduce_while(~w(docker cc), {:ok, %{}}, fn name, {:ok, found} ->
      with path when is_binary(path) <- operations.find_executable(name),
           {:ok, digest} <- operations.tool_digest(path) do
        {:cont, {:ok, Map.put(found, name, %{"path" => path, "sha256" => digest})}}
      else
        nil -> {:halt, {:error, {:missing_software_tool, name}}}
        error -> {:halt, error}
      end
    end)
  end

  defp identity(workspace, tools, inputs) do
    %{
      "inputs" => inputs,
      "tools" => tools,
      "downloads" =>
        Map.new(@downloads, fn {name, url, sha256} ->
          {name, %{"url" => url, "sha256" => sha256}}
        end),
      "tags" => Map.new(@layers, &{Atom.to_string(&1), tag(workspace, &1)})
    }
  end

  defp state(workspace) do
    case File.ls(workspace) do
      {:error, :enoent} ->
        :empty

      {:ok, []} ->
        :empty

      {:ok, names} ->
        if @lock in names, do: {:error, :build_workspace_locked}, else: read(workspace)

      _ ->
        {:error, :invalid_build_workspace}
    end
  end

  defp read(workspace) do
    path = Path.join(workspace, @manifest)

    with {:ok, %File.Stat{type: :regular, size: size}} when size <= @maximum_manifest <-
           File.lstat(path),
         {:ok, bytes} <- File.read(path),
         {:ok, manifest} when is_map(manifest) <- Jason.decode(bytes) do
      {:ok, manifest}
    else
      _ -> {:error, :unrecognized_build_workspace}
    end
  end

  defp build(workspace, root, identity, operations) do
    with :ok <- File.mkdir_p(workspace),
         {:ok, lock} <- File.open(Path.join(workspace, @lock), [:write, :exclusive]) do
      File.close(lock)
      context = %{workspace: workspace, root: root, tools: identity["tools"]}

      with {:ok, evidence} <- steps(context, identity, operations),
           {:ok, ^identity} <- current_identity(context, operations),
           {:ok, manifest} <- save(workspace, identity, evidence, operations),
           :ok <- File.rm(Path.join(workspace, @lock)) do
        {:ok, %{manifest: manifest, reused: false}}
      else
        {:ok, _} -> {:error, :software_sources_changed}
        {:error, _} = error -> error
      end
    else
      _ -> {:error, :build_workspace_locked}
    end
  end

  defp current_identity(context, operations) do
    with {:ok, tools} <- tools(operations),
         {:ok, inputs} <- Fixture.inputs(context.root) do
      {:ok, identity(context.workspace, tools, inputs)}
    end
  end

  defp steps(context, identity, operations) do
    guardian = Path.join(context.workspace, "bin/build-command")
    source = Application.app_dir(:wotex_ble, "priv/bluez/native/build_command.c")

    with :ok <- directories(context.workspace),
         {:ok, _} <- bootstrap(context, source, guardian, operations),
         :ok <- downloads(context, operations),
         :ok <- contexts(context, identity),
         {:ok, images} <- images(context, identity, operations),
         {:ok, guest} <-
           guest_file(context, operations, images, :guest_build, "/opt/wbl/build.json"),
         {:ok, native} <-
           guest_file(
             context,
             operations,
             images,
             :guest_native_manifest,
             "/opt/wbl/native/native-manifest.json"
           ),
         :ok <- File.write(Path.join(context.workspace, "guest-build.json"), guest),
         :ok <- File.write(Path.join(context.workspace, "native-manifest.json"), native),
         :ok <- export(context, operations, images.public) do
      {:ok, %{"images" => images_json(images)}}
    end
  end

  defp directories(workspace) do
    ~w(bin downloads logs context/system context/bluez/virtual context/public/source)
    |> Enum.map(&File.mkdir_p(Path.join(workspace, &1)))
    |> Enum.find(:ok, &(&1 != :ok))
  end

  defp bootstrap(context, source, guardian, operations) do
    case operations.bootstrap(context.tools["cc"]["path"], source, guardian, context.workspace) do
      {:ok, result} -> {:ok, result}
      {:error, code, _} -> {:error, {code, :bootstrap}}
    end
  end

  defp downloads(context, operations) do
    Enum.reduce_while(@downloads, :ok, fn {name, url, sha256}, :ok ->
      case operations.transfer(url, Path.join([context.workspace, "downloads", name]), sha256) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:software_download_failed, name, reason}}}
      end
    end)
  end

  defp contexts(context, identity) do
    workspace = context.workspace
    assets = Path.join(context.root, "test/interop/virtual")

    copies = [
      {Path.join(assets, "Dockerfile.system"), "context/system/Dockerfile"},
      {Path.join(assets, "Dockerfile.bluez"), "context/bluez/Dockerfile"},
      {Path.join(workspace, "downloads/bluez.tar.gz"), "context/bluez/bluez.tar.gz"},
      {Path.join(context.root, "priv/bluez/native/vendor/json.hpp"), "context/bluez/json.hpp"},
      {Path.join(assets, "Dockerfile.public"), "context/public/Dockerfile"},
      {Path.join(workspace, "downloads/hex-source.tar.gz"), "context/public/hex-source.tar.gz"},
      {Path.join(workspace, "downloads/rebar-source.tar.gz"), "context/public/rebar-source.tar.gz"}
    ]

    copied =
      copies
      |> Enum.map(fn {source, target} -> copy(source, Path.join(workspace, target)) end)
      |> Enum.find(:ok, &(&1 != :ok))

    with :ok <- copied, do: sources(context, identity["inputs"])
  end

  defp sources(context, inputs) do
    parent = Path.dirname(context.root)

    Enum.reduce_while(inputs, :ok, fn {relative, %{"sha256" => sha256, "mode" => mode}}, :ok ->
      source = Path.join(parent, relative)

      target =
        case String.split(relative, "/test/interop/virtual/", parts: 2) do
          ["wotex-ble", name] -> Path.join([context.workspace, "context/bluez/virtual", name])
          _ -> Path.join([context.workspace, "context/public/source", relative])
        end

      with :ok <- copy(source, target),
           :ok <- File.chmod(target, mode),
           {:ok, ^sha256} <- Source.digest(target) do
        {:cont, :ok}
      else
        _ -> {:halt, {:error, :software_sources_changed}}
      end
    end)
  end

  defp copy(source, target) do
    with :ok <- File.mkdir_p(Path.dirname(target)),
         {:ok, %File.Stat{type: :regular}} <- File.lstat(source),
         :ok <- File.cp(source, target) do
      :ok
    else
      _ -> {:error, :software_build_filesystem}
    end
  end

  defp images(context, identity, operations) do
    tags = identity["tags"]

    layers = [
      {:system, []},
      {:bluez, ["--build-arg", "SYSTEM_IMAGE=#{tags["system"]}"]},
      {:public, ["--build-arg", "BLUEZ_IMAGE=#{tags["bluez"]}"]}
    ]

    Enum.reduce_while(layers, {:ok, %{}}, fn {layer, extra}, {:ok, built} ->
      directory = Path.join([context.workspace, "context", Atom.to_string(layer)])
      name = tags[Atom.to_string(layer)]

      {build, inspect, _} = @layer_steps[layer]
      args = ["build", "--platform", "linux/arm64", "--progress=plain", "--tag", name | extra]

      with {:ok, _} <-
             docker(
               context,
               operations,
               build,
               Enum.reverse([directory | Enum.reverse(args)]),
               600_000
             ),
           {:ok, identifier} <- image(context, operations, inspect, name) do
        {:cont, {:ok, Map.put(built, layer, %{tag: name, id: identifier})}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp guest_file(context, operations, images, id, path) do
    args = ["run", "--rm", "--network", "none", images.public.id, "cat", path]

    case docker(context, operations, id, args, 120_000) do
      {:ok, output} ->
        case Jason.decode(output) do
          {:ok, decoded} when is_map(decoded) -> {:ok, output}
          _ -> {:error, :invalid_guest_build_evidence}
        end

      error ->
        error
    end
  end

  defp export(context, operations, image) do
    name = "wotex-ble-software-export-" <> random()

    result =
      with {:ok, _} <-
             docker(
               context,
               operations,
               :export_create,
               ["create", "--name", name, "--network", "none", image.id],
               120_000
             ),
           {:ok, _} <-
             docker(
               context,
               operations,
               :export_rootfs,
               ["export", "--output", Path.join(context.workspace, "rootfs.tar"), name],
               600_000
             ) do
        :ok
      end

    removed = docker(context, operations, :export_remove, ["rm", "-f", name], 60_000)

    with :ok <- result,
         {:ok, _} <- removed,
         {:ok, _} <-
           docker(
             context,
             operations,
             :filesystem,
             [
               "run",
               "--rm",
               "--name",
               "wotex-ble-software-filesystem-" <> random(),
               "--network",
               "none",
               "--mount",
               "type=bind,src=#{context.workspace},target=/work",
               image.id,
               "bash",
               "/opt/wbl/fixture/make_filesystem.sh"
             ],
             600_000
           ) do
      :ok
    end
  end

  defp images_json(images),
    do:
      Map.new(images, fn {layer, %{tag: tag, id: id}} ->
        {Atom.to_string(layer), %{"tag" => tag, "id" => id}}
      end)

  defp save(workspace, identity, evidence, operations) do
    with {:ok, artifacts} <- artifacts(workspace, operations),
         {:ok, guest} <- decode_file(Path.join(workspace, "guest-build.json")),
         {:ok, native} <- decode_file(Path.join(workspace, "native-manifest.json")) do
      manifest = %{
        "schema" => "wotex.ble.software-build",
        "version" => 1,
        "identity" => identity,
        "images" => evidence["images"],
        "artifacts" => artifacts,
        "guest" => guest,
        "native" => native
      }

      bytes = Jason.encode!(manifest)

      if byte_size(bytes) <= @maximum_manifest and
           File.write(Path.join(workspace, @manifest), bytes <> "\n", [:exclusive]) == :ok,
         do: {:ok, Jason.decode!(bytes)},
         else: {:error, :invalid_build_manifest}
    end
  end

  defp decode_file(path) do
    with {:ok, bytes} <- File.read(path), {:ok, value} when is_map(value) <- Jason.decode(bytes) do
      {:ok, value}
    else
      _ -> {:error, :invalid_guest_build_evidence}
    end
  end

  defp artifacts(workspace, operations) do
    logs =
      case File.ls(Path.join(workspace, "logs")) do
        {:ok, names} -> Enum.map(names, &"logs/#{&1}")
        _ -> []
      end

    names =
      Enum.map(@downloads, fn {name, _, _} -> "downloads/" <> name end) ++
        ~w(rootfs.tar rootfs.raw guest-build.json native-manifest.json bin/build-command) ++ logs

    Enum.reduce_while(Enum.sort(names), {:ok, %{}}, fn relative, {:ok, found} ->
      path = Path.join(workspace, relative)

      with {:ok, %File.Stat{type: :regular}} <- File.lstat(path),
           {:ok, digest} <- operations.digest(path) do
        {:cont, {:ok, Map.put(found, relative, digest)}}
      else
        _ -> {:halt, {:error, :invalid_software_artifact}}
      end
    end)
  end

  defp verify(workspace, identity, manifest, operations) do
    context = %{workspace: workspace, tools: identity["tools"]}

    with true <-
           Map.keys(manifest) |> Enum.sort() ==
             ~w(artifacts guest identity images native schema version),
         true <- manifest["schema"] == "wotex.ble.software-build" and manifest["version"] == 1,
         true <- manifest["identity"] == Jason.decode!(Jason.encode!(identity)),
         {:ok, artifacts} <- artifacts_without_logs(workspace, manifest, operations),
         true <- artifacts == manifest["artifacts"],
         :ok <- verify_images(context, manifest["images"], identity["tags"], operations) do
      {:ok, %{manifest: manifest, reused: true}}
    else
      _ -> {:error, :build_manifest_mismatch}
    end
  end

  # Reuse recomputes recorded artifacts only. Verification commands write no
  # log, so a verified workspace keeps every recorded digest unchanged.
  defp artifacts_without_logs(workspace, manifest, operations) do
    Enum.reduce_while(manifest["artifacts"] || %{}, {:ok, %{}}, fn {relative, _}, {:ok, found} ->
      path = Path.join(workspace, relative)

      with true <- is_binary(relative) and not String.contains?(relative, ".."),
           {:ok, %File.Stat{type: :regular}} <- File.lstat(path),
           {:ok, digest} <- operations.digest(path) do
        {:cont, {:ok, Map.put(found, relative, digest)}}
      else
        _ -> {:halt, :error}
      end
    end)
  end

  defp verify_images(context, images, tags, operations) when is_map(images) do
    Enum.reduce_while(@layers, :ok, fn layer, :ok ->
      key = Atom.to_string(layer)

      with %{"tag" => tag, "id" => id} <- images[key],
           true <- tag == tags[key],
           {:ok, ^id} <- inspect_verified(context, operations, layer, tag) do
        {:cont, :ok}
      else
        _ -> {:halt, :error}
      end
    end)
  end

  defp verify_images(_, _, _, _), do: :error

  defp inspect_verified(context, operations, layer, tag) do
    {_, _, verify} = @layer_steps[layer]

    step = %{
      id: verify,
      executable: context.tools["docker"]["path"],
      args: ["image", "inspect", tag],
      cwd: context.workspace,
      env: environment(context.tools),
      timeout_ms: 60_000,
      output_bytes: 1_048_576,
      cleanup_ms: 5000
    }

    with {:ok, %{output: output}} <-
           operations.command(Path.join(context.workspace, "bin/build-command"), step),
         {:ok, [%{"Id" => id, "Architecture" => "arm64", "Os" => "linux"}]} <-
           Jason.decode(output) do
      {:ok, id}
    else
      _ -> :error
    end
  end

  defp random, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
end
