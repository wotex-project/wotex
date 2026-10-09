Code.require_file("bridge_model.exs", __DIR__)

defmodule Wotex.Matter.SoftwareBridgeBuild do
  @moduledoc false

  alias Wotex.Matter.{SoftwareBridgeModel, SoftwareManifest}

  @target "obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-server-test"
  @environment [
    {"ASAN_OPTIONS", "detect_leaks=1:halt_on_error=1"},
    {"UBSAN_OPTIONS", "halt_on_error=1"}
  ]
  @cases [
    {"normal", 0, "server startup and shutdown probe passed"},
    {"reopen", 0, "server startup and shutdown probe passed"},
    {"poison_sdk", 74, nil},
    {"poison_allocate", 74, nil},
    {"poison_remove", 74, nil},
    {"startup_failure", 70, nil},
    {"missing_finish", 70, nil},
    {"wrong_model", 0, "server input refusal probe passed"},
    {"wrong_vendor", 0, "server input refusal probe passed"},
    {"wrong_product", 0, "server input refusal probe passed"},
    {"missing_dac", 0, "server input refusal probe passed"},
    {"endpoints_seed", 0,
     [
       "bridge endpoint metadata, custody and observations passed",
       "bridge endpoint event loop and shutdown passed"
     ]},
    {"endpoints_reopen", 0,
     [
       "bridge endpoint metadata, custody and observations passed",
       "bridge endpoint event loop and shutdown passed"
     ]},
    {"endpoints_missing_finish", 70, "bridge endpoint metadata, custody and observations passed"},
    {"endpoints_poison_add", 74, "bridge endpoint metadata, custody and observations passed"},
    {"endpoints_poison_remove", 74, "bridge endpoint metadata, custody and observations passed"},
    {"handoff", 0, "bridge handoff event loop and shutdown passed"},
    {"handoff_pending_finish", 70, "bridge handoff retained context prepared"},
    {"handoff_closed_init", 0, "server input refusal probe passed"},
    {"handoff_busy_init", 0, "server input refusal probe passed"}
  ]
  # Arguments remain positional, including paths with shell metacharacters.
  # The outer build runner records the command and bounds its output/deadline.
  @exit_check """
  expected=$1
  shift
  timeout 20 "$@"
  actual=$?
  printf '\nbridge server exit: %s\n' "$actual"
  test "$actual" -eq "$expected"
  """

  @spec arguments() :: String.t()
  def arguments do
    profile = SoftwareBridgeModel.profile()

    defines =
      profile["selected_build_arguments"]["target_defines"] ++
        profile["test_attestation"]["build_defines"] ++
        [
          ~s(CHIP_CONFIG_KVS_PATH="bridge-kvs"),
          ~s(CHIP_DEFAULT_FACTORY_PATH="bridge-factory.ini"),
          ~s(CHIP_DEFAULT_CONFIG_PATH="bridge-config.ini"),
          ~s(CHIP_DEFAULT_DATA_PATH="bridge-counters.ini")
        ]

    profile["selected_build_arguments"]
    |> Map.put("target_defines", defines)
    |> Map.put("chip_logging_backend", "external")
    |> Enum.sort()
    |> Enum.map_join("", fn {key, value} -> key <> " = " <> Jason.encode!(value) <> "\n" end)
  end

  @spec run!(String.t(), (String.t(), [String.t()], [{String.t(), String.t()}] -> binary())) ::
          map()
  def run!(workspace, inside) do
    sdk = Path.join(workspace, "sdk")
    generated = Path.join(workspace, "bridge-model")
    SoftwareBridgeModel.generate!(sdk, Path.join(workspace, "tools"), generated)
    destination = Path.join(sdk, "examples/wotex-matter-host/bridge-common")
    File.mkdir!(destination)
    File.cp!(Path.join(generated, "bridge-app.zap"), Path.join(destination, "bridge-app.zap"))

    File.cp!(
      Path.join(generated, "idl/Clusters.matter"),
      Path.join(destination, "bridge-app.matter")
    )

    builds =
      for {directory, sanitizer} <- [
            {"build-bridge", ""},
            {"build-bridge-sanitized", "is_asan = true\nis_ubsan = true\n"}
          ] do
        File.mkdir!(Path.join(workspace, directory))
        File.mkdir!(Path.join([workspace, directory, "stores"]))
        File.chmod!(Path.join([workspace, directory, "stores"]), 0o700)
        File.write!(Path.join([workspace, directory, "args.gn"]), arguments() <> sanitizer)

        inside.(
          directory <> "-generate",
          ["/work/tools/gn/gn", "--root=/work/sdk", "gen", "/work/" <> directory],
          []
        )

        inside.(
          directory <> "-compile",
          ["ninja", "--quiet", "-C", "/work/" <> directory, "-j", "4", @target],
          []
        )

        compiled_model =
          for {path, expected} <- SoftwareBridgeModel.profile()["generated_sha256"], into: %{} do
            source =
              if String.starts_with?(path, "cpp/") do
                Path.join([
                  workspace,
                  directory,
                  "gen/examples/wotex-matter-host/zapgen/zap-generated",
                  Path.basename(path)
                ])
              else
                Path.join(destination, "bridge-app.matter")
              end

            actual = SoftwareManifest.digest(source)
            unless actual == expected, do: Mix.raise("bridge_server_model_mismatch")
            {path, actual}
          end

        cases =
          for {mode, expected, receipt} <- @cases do
            store =
              case mode do
                "reopen" -> "normal"
                "endpoints_reopen" -> "endpoints_seed"
                other -> other
              end

            directory_path = "/work/" <> directory <> "/stores/" <> store
            binary = "/work/" <> directory <> "/" <> @target

            output =
              inside.(
                directory <> "-case-" <> mode,
                [
                  "/bin/sh",
                  "-c",
                  @exit_check,
                  "bridge-server-test",
                  Integer.to_string(expected),
                  binary,
                  directory_path,
                  mode
                ],
                @environment
              )

            verify_case!(output, expected, receipt)
            %{"mode" => mode, "exit_status" => expected}
          end

        {directory,
         %{
           "binary_sha256" => SoftwareManifest.digest(Path.join([workspace, directory, @target])),
           "generated_sha256" => compiled_model,
           "cases" => cases
         }}
      end

    %{
      "model_sha256" => SoftwareBridgeModel.profile()["model_sha256"],
      "generated_sha256" => SoftwareBridgeModel.profile()["generated_sha256"],
      "builds" => Map.new(builds)
    }
  end

  @spec verify_case!(binary(), integer(), String.t() | [String.t()] | nil) :: :ok
  def verify_case!(output, expected, receipt) do
    unless String.ends_with?(output, "\nbridge server exit: #{expected}\n") and
             Enum.all?(List.wrap(receipt), &(&1 in String.split(output, "\n"))) and
             not Regex.match?(
               ~r/AddressSanitizer|LeakSanitizer|runtime error:|UndefinedBehaviorSanitizer/,
               output
             ),
           do: Mix.raise("bridge_server_test_failed")

    :ok
  end
end
