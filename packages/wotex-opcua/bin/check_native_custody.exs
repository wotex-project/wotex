defmodule Wotex.OPCUA.Check.NativeCustody do
  @moduledoc false

  @prefix "wotex-opcua-native-custody."
  @fixture "priv/fixtures/custody-contract-v1.json"
  @sanitizer_flags ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]

  @spec main() :: :ok
  def main do
    if :os.type() == {:unix, :linux} do
      verify_linux!()
    else
      IO.puts("Linux custody sanitizer lanes are not applicable on this host")
    end
  end

  defp verify_linux! do
    compiler = System.find_executable("cc") || fail("Linux custody audit requires a C11 compiler")
    native = Application.app_dir(:wotex_opcua, "priv/native")
    work = Path.join(System.tmp_dir!(), @prefix <> unique())

    try do
      File.mkdir!(work)
      guardian = compile!(compiler, native, work, "custody")
      checker = compile!(compiler, native, work, "custody_check")
      cases = Jason.decode!(File.read!(@fixture))["cases"]

      unless Enum.map(cases, & &1["id"]) ==
               Enum.map(1..9, &("WOP-G" <> String.pad_leading(Integer.to_string(&1), 2, "0"))) do
        fail("custody fixture does not contain the exact WOP-G01..WOP-G09 corpus")
      end

      for lane <- [:strict, :leak], fixture <- cases do
        execute!(checker, guardian, work, lane, fixture)
      end

      IO.puts("Linux custody sanitizer lanes passed: 18 executions")
      :ok
    after
      cleanup(work)
    end
  end

  defp compile!(compiler, native, work, name) do
    output = Path.join(work, name)

    run!(
      compiler,
      [
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-Werror"
        | @sanitizer_flags ++ [Path.join(native, name <> ".c"), "-o", output]
      ],
      work,
      [{"CFLAGS", nil}, {"LDFLAGS", nil}]
    )

    output
  end

  defp execute!(checker, guardian, work, lane, fixture) do
    id = fixture["id"]
    directory = Path.join(work, "#{lane}-#{id}")
    File.mkdir!(directory)

    {arguments, asan, allowance} =
      case lane do
        :strict ->
          {[guardian, id, directory], "detect_leaks=0:abort_on_error=1", 0}

        :leak ->
          {[guardian, id, directory, "--leak-audit"], "detect_leaks=1:abort_on_error=1", 1000}
      end

    output =
      run!(checker, arguments, work, [
        {"ASAN_OPTIONS", asan},
        {"LSAN_OPTIONS", "exitcode=23"},
        {"UBSAN_OPTIONS", "halt_on_error=1:print_stacktrace=1"}
      ])

    result = Jason.decode!(String.trim(output))
    expected = fixture["expectation"]

    unless result["case"] == id and result["status"] == expected["status"] and
             result["input_capacity"] == fixture["input_capacity"] and
             result["output_capacity"] == fixture["output_capacity"] and
             result["received_bytes"] == expected["received_bytes"] and
             result["direct_reaped"] == expected["direct_reaped"] and
             result["background_stopped"] == expected["background_stopped"] and
             result["cleanup_ms"] in 0..fixture["cleanup_allowance_ms"] and
             result["guardian_exit_ms"] in 0..(fixture["cleanup_allowance_ms"] + allowance) and
             result["instrumented_exit_allowance_ms"] == allowance and
             sent_bytes?(result["sent_bytes"], expected["sent_bytes"], fixture) do
      fail("#{lane} #{id} did not match the custody contract")
    end
  end

  defp sent_bytes?(actual, %{"operator" => "exact", "value" => expected}, _fixture),
    do: actual == expected

  defp sent_bytes?(actual, %{"operator" => "positive"}, fixture),
    do: actual > fixture["input_capacity"]

  defp sent_bytes?(_, _, _), do: false

  defp run!(command, arguments, directory, environment) do
    {output, status} =
      System.cmd(command, arguments,
        cd: directory,
        env: environment,
        stderr_to_stdout: true
      )

    unless status == 0 do
      fail(
        "#{Path.basename(command)} failed with status #{status}: #{String.slice(output, 0, 4096)}"
      )
    end

    output
  end

  defp cleanup(work) do
    if String.starts_with?(work, Path.join(System.tmp_dir!(), @prefix)) do
      File.rm_rf!(work)
    else
      fail("refusing unsafe custody-check cleanup")
    end
  end

  defp unique, do: Integer.to_string(System.unique_integer([:positive]))
  defp fail(message), do: raise(message)
end

Wotex.OPCUA.Check.NativeCustody.main()
