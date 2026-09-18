defmodule Wotex.Workspace.ToolchainTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace
  alias Wotex.Workspace.Manifest

  # The `[tools]` table of mise.toml as a map. The file holds only quoted
  # `key = "value"` pairs, so a line reader is enough.
  defp mise_tools do
    Workspace.root()
    |> Path.join("mise.toml")
    |> File.read!()
    |> String.split("\n")
    |> Enum.reduce({nil, %{}}, fn line, {section, tools} ->
      line = String.trim(line)

      cond do
        String.starts_with?(line, "[") ->
          {String.trim(String.trim(line, "["), "]"), tools}

        section == "tools" and line =~ ~r/^"?[^"=]+"?\s*=\s*"[^"]*"$/ ->
          [key, value] = String.split(line, "=", parts: 2)
          {section, Map.put(tools, trim_quotes(key), trim_quotes(value))}

        true ->
          {section, tools}
      end
    end)
    |> elem(1)
  end

  defp trim_quotes(text), do: String.trim(String.trim(text), "\"")

  test "mise.toml pins the current lane of tooling/packages.yaml and Dexter" do
    {:ok, current} = Manifest.lane("current", Manifest.load!())
    tools = mise_tools()

    assert tools["erlang"] == current.otp
    assert tools["elixir"] == current.elixir
    assert tools["aqua:remoteoss/dexter"] =~ ~r/^\d+\.\d+\.\d+$/
  end

  test "mise.toml and rust-toolchain.toml pin one Rust toolchain with rustfmt and clippy" do
    toolchain = File.read!(Path.join(Workspace.root(), "rust-toolchain.toml"))
    assert [_, channel] = Regex.run(~r/^channel = "([^"]+)"$/m, toolchain)
    assert channel =~ ~r/^\d+\.\d+\.\d+$/
    assert mise_tools()["rust"] == channel
    assert toolchain =~ ~r/^components = \["rustfmt", "clippy"\]$/m
  end

  test "the native toolchain configuration selects every package when it changes" do
    select_all_on = Manifest.load!().select_all_on

    for file <- ~w(rust-toolchain.toml .clang-format .clang-format-ignore .clang-tidy) do
      assert File.regular?(Path.join(Workspace.root(), file))
      assert file in select_all_on
    end
  end

  test "mise.toml replaces .tool-versions and selects every package when it changes" do
    refute File.exists?(Path.join(Workspace.root(), ".tool-versions"))
    assert "mise.toml" in Manifest.load!().select_all_on
  end

  defp read(relative), do: File.read!(Path.join(Workspace.root(), relative))

  defp llvm_major(text) do
    [_, major] = Regex.run(~r/^\s*(?:ARG )?LLVM_MAJOR[=:] ?"?(\d+)"?$/m, text)
    major
  end

  test "the Linux image of the native checks pins the current lane by digest" do
    {:ok, current} = Manifest.lane("current", Manifest.load!())
    dockerfile = read("tooling/native/docker/linux.Dockerfile")

    assert [_, elixir, otp] =
             Regex.run(
               ~r|^FROM hexpm/elixir:(\d+\.\d+\.\d+)-erlang-([\d.]+)-ubuntu-noble-[\d.]+@sha256:[0-9a-f]{64}$|m,
               dockerfile
             )

    [otp_major | _] = String.split(otp, ".")
    assert current.elixir == "#{elixir}-otp-#{otp_major}"
    assert current.otp == otp
    assert dockerfile =~ "grep -q \"^Elixir #{String.replace(elixir, ".", "\\.")} \""
    assert dockerfile =~ ~r/test "\$\(gcc -dumpversion \| cut -d\. -f1\)" = 13/
  end

  test "the native images install the LLVM major version CI installs" do
    ci = llvm_major(read(".github/workflows/ci.yml"))

    for dockerfile <- ~w(linux matter-sdk) do
      assert llvm_major(read("tooling/native/docker/#{dockerfile}.Dockerfile")) == ci
    end
  end

  test "the Matter clang-tidy image starts from the image the Matter SDK build runs in" do
    [_, image] =
      Regex.run(
        ~r/@image "([^"]+)"/,
        read("packages/wotex-matter/test/support/software/manifest.exs")
      )

    assert read("tooling/native/docker/matter-sdk.Dockerfile") =~ ~r/^FROM #{Regex.escape(image)}$/m
  end

  test "CI reads the lanes, the native packages and Rust instead of repeating them" do
    ci = read(".github/workflows/ci.yml")
    manifest = Manifest.load!()

    for {_name, lane} <- manifest.lanes, version <- [lane.elixir, lane.otp] do
      refute ci =~ version, "ci.yml repeats #{version} from tooling/packages.yaml"
    end

    for package <- Manifest.native_packages(manifest) do
      refute ci =~ ~r/[\[ ,]#{package.name}[\], ]/, "ci.yml lists #{package.name}"
    end

    [_, channel] = Regex.run(~r/^channel = "([^"]+)"$/m, read("rust-toolchain.toml"))
    refute ci =~ channel

    assert ci =~ "lane: ${{ fromJSON(needs.manifest.outputs.lanes) }}"
    assert ci =~ "package: ${{ fromJSON(needs.manifest.outputs.native) }}"
    assert ci =~ "yq -o=json -I=0 '.lanes | keys' \"$manifest\""
  end

  test "the Dexter index is ignored" do
    ignored = File.read!(Path.join(Workspace.root(), ".gitignore"))
    assert ".dexter/" in String.split(ignored, "\n")
  end
end
