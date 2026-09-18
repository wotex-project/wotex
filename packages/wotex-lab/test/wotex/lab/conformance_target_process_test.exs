defmodule Wotex.Lab.ConformanceTargetProcessTest do
  @moduledoc false

  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  test "the process entry exchanges UTF-8 request and response bytes under any locale",
       %{tmp_dir: tmp_dir} do
    archive = Path.join(tmp_dir, "subject.tar")
    File.write!(archive, "archive")

    document = %{
      "@context" => Wotex.td_context_1_1(),
      "title" => "Väderstation ☀",
      "security" => ["nosec_sc"],
      "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}}
    }

    {:ok, line} =
      Wotex.JSON.encode(%{
        "claim" => %{"operation" => "thing_description.parse"},
        "vector" => %{
          "id" => "utf8",
          "input" => %{"document" => document, "projection" => ["/title"]}
        }
      })

    for locale <- ["C", "C.UTF-8", "en_US.UTF-8"] do
      assert {0, output} = run_target(archive, line, locale)

      assert {:ok,
              %{
                "vector_id" => "utf8",
                "outcome" => "observed",
                "actual" => %{"accepted" => true, "document" => %{"/title" => "Väderstation ☀"}}
              }} = Wotex.JSON.decode(String.trim_trailing(output))
    end
  end

  test "the process entry rejects a request that is not UTF-8 under any locale",
       %{tmp_dir: tmp_dir} do
    archive = Path.join(tmp_dir, "subject.tar")
    File.write!(archive, "archive")

    line =
      ~s({"claim":{"operation":"thing_description.parse"},"vector":{"id":"latin1",) <>
        ~s("input":{"document":{"title":"V\xE4derstation"}}}})

    refute String.valid?(line)

    for locale <- ["C", "C.UTF-8", "en_US.UTF-8"] do
      assert {14, ""} = run_target(archive, line, locale)
    end
  end

  defp run_target(archive, line, locale) do
    erl = Path.join([to_string(:code.root_dir()), "bin", "erl"])

    paths =
      Enum.flat_map([:elixir, :wotex, :jason, :ex_json_schema, :wotex_lab, :telemetry], fn app ->
        ["-pa", Application.app_dir(app, "ebin")]
      end)

    eval =
      "application:ensure_all_started(elixir), " <>
        "'Elixir.Wotex.Lab.Conformance.Target':main([unicode:characters_to_binary(A) || A <- init:get_plain_arguments()])"

    port =
      Port.open({:spawn_executable, erl}, [
        :binary,
        :exit_status,
        args: ["-noshell"] ++ paths ++ ["-eval", eval, "-extra", "--archive", archive],
        env: [{~c"LANG", String.to_charlist(locale)}, {~c"LC_ALL", String.to_charlist(locale)}]
      ])

    Port.command(port, line <> "\n")
    collect(port, "")
  end

  defp collect(port, output) do
    receive do
      {^port, {:data, bytes}} -> collect(port, output <> bytes)
      {^port, {:exit_status, status}} -> {status, output}
    after
      15_000 -> flunk("target process did not exit")
    end
  end
end
