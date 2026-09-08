defmodule Wotex.Lab.Check.NervesSource do
  @moduledoc false

  @files ~w(
    .formatter.exs
    .gitignore
    README.md
    config/config.exs
    lib/wotex_lab_nerves/application.ex
    lib/wotex_lab_nerves/smoke.ex
    mix.exs
    mix.lock
    test/smoke_test.exs
    test/test_helper.exs
  )

  @pins [
    ~s({:nerves, "1.15.0", runtime: false}),
    ~s({:nerves_system_rpi4, "2.1.1", runtime: false, targets: :rpi4}),
    ~s("nerves": {:hex, :nerves, "1.15.0"),
    ~s("nerves_system_rpi4": {:hex, :nerves_system_rpi4, "2.1.1"),
    ~s("nerves_toolchain_aarch64_nerves_linux_gnu": {:hex, :nerves_toolchain_aarch64_nerves_linux_gnu, "15.3.1")
  ]

  @forbidden [
    "/" <> "Users/",
    "/" <> "home/",
    "BEGIN " <> "PRIVATE KEY",
    "WOTEX_PATH_DEPS=1 " <> "MIX_ENV=prod"
  ]

  def run do
    root = Path.expand("../hosts/nerves", __DIR__)
    actual = source_files(root)

    actual == Enum.sort(@files) ||
      abort(
        "Nerves source cohort differs: " <>
          inspect(%{extra: actual -- @files, missing: @files -- actual})
      )

    source = Enum.map_join(@files, "\n", &File.read!(Path.join(root, &1)))
    Enum.each(@pins, &(String.contains?(source, &1) || abort("Nerves source lacks pin #{&1}")))

    application = File.read!(Path.join(root, "lib/wotex_lab_nerves/application.ex"))
    smoke = File.read!(Path.join(root, "lib/wotex_lab_nerves/smoke.ex"))
    public_source = application <> smoke <> File.read!(Path.join(root, "mix.exs"))

    Enum.each(
      @forbidden,
      &(!String.contains?(public_source, &1) || abort("Nerves source contains #{&1}"))
    )

    String.contains?(application, "Wotex.Lab.child_spec") || abort("firmware lacks explicit Lab")
    !String.contains?(application, "Thermal.run") || abort("firmware runs an experiment at boot")
    String.contains?(smoke, "Nx.BinaryBackend") || abort("smoke lacks the binary backend")
    !String.contains?(smoke, "invoke_action") || abort("smoke contains an Action dispatch")

    String.contains?(smoke, "status: if(target == :rpi4, do: :pass, else: :not_run)") ||
      abort("host smoke does not preserve the hardware non-claim")

    digest = :crypto.hash(:sha256, source) |> Base.encode16(case: :lower)
    IO.puts("Nerves source: rpi4 target, locked toolchain and inert host smoke sha256:#{digest}")
  end

  defp source_files(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
    |> Enum.map(&Path.relative_to(&1, root))
    |> Enum.reject(&String.starts_with?(&1, ["_build/", "deps/"]))
    |> Enum.sort()
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Lab.Check.NervesSource.run()
