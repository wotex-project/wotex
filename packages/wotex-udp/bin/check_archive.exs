defmodule Wotex.UDP.Check.Archive do
  @moduledoc """
  Builds the exact package archive, inspects its members, and exercises it
  through an isolated Mix consumer with no live source path dependency.
  """

  @prefix "wotex-udp-archive."
  @required ~w(.formatter.exs CHANGELOG.md LICENSE NOTICE README.md usage-rules.md mix.exs)
  @forbidden ~r{(^|/)(\.check\.exs|\.agents|\.claude|\.codex|\.git|\.github|AGENTS\.md|CLAUDE\.md|bin|cover|deps|doc|docs|mix\.lock|test|_build)(/|$)}

  @spec main() :: :ok
  def main do
    workspace =
      Path.join(System.tmp_dir!(), @prefix <> Integer.to_string(System.unique_integer([:positive])))

    File.mkdir_p!(workspace)

    try do
      archive = Path.join(workspace, "wotex_udp-0.1.0.tar")
      run!("mix", ["hex.build", "--output", archive], File.cwd!(), release_env())
      contents = inspect_archive!(archive)
      extracted = Path.join(workspace, "extracted")
      File.mkdir_p!(extracted)

      :ok =
        :erl_tar.extract({:binary, contents}, [:compressed, {:cwd, String.to_charlist(extracted)}])

      consumer = Path.join(workspace, "consumer")
      write_consumer!(consumer, extracted)
      run!("mix", ["deps.get"], consumer, release_env())
      run!("mix", ["test", "--warnings-as-errors"], consumer, release_env())
      IO.puts("wotex_udp archive sha256=#{digest(archive)}")
      :ok
    after
      File.rm_rf!(workspace)
    end
  end

  defp inspect_archive!(archive) do
    {:ok, outer} = :erl_tar.extract(String.to_charlist(archive), [:memory])
    {_, contents} = List.keyfind(outer, ~c"contents.tar.gz", 0)
    {:ok, members} = :erl_tar.extract({:binary, contents}, [:compressed, :memory])
    names = Enum.map(members, fn {name, _} -> List.to_string(name) end)

    Enum.each(@required ++ ["lib/wotex/udp.ex"], fn path ->
      unless path in names, do: raise("archive is missing #{path}")
    end)

    if Enum.any?(names, fn path ->
         Path.type(path) == :absolute or ".." in Path.split(path) or
           Regex.match?(@forbidden, path)
       end) do
      raise "archive contains an unsafe or development-only member"
    end

    contents
  end

  defp write_consumer!(consumer, extracted) do
    File.mkdir_p!(Path.join(consumer, "test"))

    File.write!(Path.join(consumer, "mix.exs"), """
    defmodule WotexUDPArchiveConsumer.MixProject do
      use Mix.Project
      def project do
        [app: :wotex_udp_archive_consumer, version: "0.0.0", elixir: "~> 1.18",
         deps: [{:wotex_udp, path: #{inspect(extracted)}}]]
      end
      def application, do: [extra_applications: []]
    end
    """)

    File.write!(Path.join(consumer, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(Path.join(consumer, "test/consumer_test.exs"), """
    defmodule WotexUDPArchiveConsumerTest do
      use ExUnit.Case

      test "the archive supplies a working owner and loopback transport" do
        assert Application.load(:wotex_udp) in [:ok, {:error, {:already_loaded, :wotex_udp}}]
        assert Application.spec(:wotex_udp, :mod) in [nil, [], :undefined]
        {:ok, local} = Wotex.UDP.Endpoint.bind({127, 0, 0, 1}, 0)
        {:ok, config} = Wotex.UDP.Config.new(local: local)
        {:ok, handle} = Wotex.UDP.open(config)
        {:ok, destination} = Wotex.UDP.local(handle)
        assert :ok = Wotex.UDP.send(handle, destination, <<0, 255>>, 100)
        assert {:ok, %{data: <<0, 255>>}} = Wotex.UDP.recv(handle, 100)
        assert :ok = Wotex.UDP.close(handle)
      end
    end
    """)
  end

  defp run!(command, arguments, directory, environment) do
    {_output, status} =
      System.cmd(command, arguments,
        cd: directory,
        env: environment,
        into: IO.stream(),
        stderr_to_stdout: true
      )

    unless status == 0, do: raise("#{command} #{Enum.join(arguments, " ")} failed")
  end

  defp release_env,
    do: [{"WOTEX_PATH_DEPS", nil}, {"MIX_ENV", "test"}, {"MIX_PATH", nil}, {"ERL_LIBS", nil}]

  defp digest(path) do
    :sha256 |> :crypto.hash(File.read!(path)) |> Base.encode16(case: :lower)
  end
end

Wotex.UDP.Check.Archive.main()
