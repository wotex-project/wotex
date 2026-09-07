defmodule Wotex.Check.Package do
  @moduledoc false

  @present [
    "mix.exs",
    "README.md",
    "LICENSE",
    "NOTICE",
    "priv/w3c/td-json-schema-validation-1.1.json"
  ]

  @absent ["CLAUDE.md", ".claude"]

  @callback_probe """
  Application.load(:wotex)

  unless Application.spec(:wotex, :mod) in [nil, [], :undefined] do
    raise "archive defines an application callback"
  end

  IO.puts("unpacked archive compiled without an application callback")
  """

  @spec main() :: :ok
  def main do
    package_root = Path.join(System.tmp_dir!(), "wotex-package.#{unique()}")

    result =
      try do
        verify(Path.join(package_root, "unpacked"))
      catch
        :throw, {:violation, message} -> {:violation, message}
      after
        File.rm_rf!(package_root)
      end

    report(result)
  end

  defp unique, do: Integer.to_string(System.unique_integer([:positive]))

  defp verify(unpacked) do
    run!("mix", ["hex.build", "--unpack", "--output", unpacked], File.cwd!())

    Enum.each(@present, &present!(unpacked, &1))
    Enum.each(@absent, &absent!(unpacked, &1))

    run!("mix", ["deps.get"], unpacked)
    run!("mix", ["compile", "--warnings-as-errors"], unpacked)
    run!("mix", ["run", "--no-start", "-e", @callback_probe], unpacked)

    :ok
  end

  defp present!(unpacked, entry) do
    unless File.regular?(Path.join(unpacked, entry)) do
      violation("packaged archive is missing #{entry}")
    end
  end

  defp absent!(unpacked, entry) do
    if File.exists?(Path.join(unpacked, entry)) do
      violation("packaged archive contains #{entry}")
    end
  end

  defp run!(command, arguments, directory) do
    options = [
      cd: directory,
      env: [{"MIX_ENV", "prod"}],
      into: IO.stream(),
      stderr_to_stdout: true
    ]

    {_output, status} = System.cmd(command, arguments, options)

    unless status == 0 do
      violation("#{command} #{Enum.join(arguments, " ")} failed in the unpacked archive")
    end
  end

  defp violation(message), do: throw({:violation, message})

  defp report(:ok), do: :ok

  defp report({:violation, message}) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Check.Package.main()
