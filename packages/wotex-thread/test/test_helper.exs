Code.require_file("support/client.ex", __DIR__)

# The explicit software runner selects fixtures through the environment; required
# configuration missing under WOTEX_REQUIRE_SOFTWARE is a failure, never a skip.
case System.get_env("WOTEX_REQUIRE_SOFTWARE") do
  nil ->
    ExUnit.start(exclude: [:interop, :hardware, :software])

  "1" ->
    required = ~w(WOTEX_THREAD_HOST WOTEX_THREAD_RCP WOTEX_THREAD_CONTRACT_DRIVER
      WOTEX_THREAD_DATASET_SEED WOTEX_THREAD_CASE_RESULTS)

    case Enum.reject(required, &System.get_env/1) do
      [] ->
        :ok

      missing ->
        raise "required software fixture configuration is missing: #{Enum.join(missing, ", ")}"
    end

    Code.require_file("support/software_cases.ex", __DIR__)

    ExUnit.start(
      exclude: [:hardware],
      include: [:interop, :software],
      formatters: [ExUnit.CLIFormatter, Wotex.Thread.SoftwareCases]
    )

  _ ->
    raise "WOTEX_REQUIRE_SOFTWARE must be unset or equal to 1"
end
