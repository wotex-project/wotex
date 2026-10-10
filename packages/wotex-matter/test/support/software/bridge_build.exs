Code.require_file("bridge_model.exs", __DIR__)

defmodule Wotex.Matter.SoftwareBridgeBuild do
  @moduledoc false

  alias Wotex.Matter.{SoftwareBridgeModel, SoftwareManifest}

  @target "obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-server-test"
  @codec "obj/examples/wotex-matter-host/bin/wotex-matter-bridge-codec-test"
  @configuration "obj/examples/wotex-matter-host/bin/wotex-matter-bridge-configuration-test"
  @bootstrap "obj/examples/wotex-matter-host/bin/wotex-matter-bridge-bootstrap-test"
  @lifecycle "obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test"
  @environment [
    {"ASAN_OPTIONS", "detect_leaks=1:halt_on_error=1"},
    {"UBSAN_OPTIONS", "halt_on_error=1"}
  ]
  @cases [
    {"credentials", 0, "explicit bridge credential ownership and refusal passed"},
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
    {"handoff_busy_init", 0, "server input refusal probe passed"},
    {"requests", 0,
     [
       "bridge owned request metadata and arguments passed",
       "bridge request event loop responses passed",
       "bridge request handles, responses and shutdown passed"
     ]},
    {"requests_invalidated", 0,
     [
       "bridge owned request metadata and arguments passed",
       "bridge request event loop responses passed",
       "bridge request handles, responses and shutdown passed"
     ]},
    {"replies", 0,
     [
       "bridge reply scope and encoding boundaries passed",
       "bridge captured principal Groups and Scenes replies passed"
     ]},
    {"replies_retain", 70, "bridge reply child-handle refusal prepared"},
    {"provider", 0, "installed SDK provider routing and notifications passed"},
    {"provider_startup_failure", 70, "bridge provider partial startup refusal prepared"},
    {"provider_shutdown_failure", 70, "bridge provider failed shutdown refusal prepared"},
    {"provider_missing_finish", 70, "bridge provider missing shutdown refusal prepared"},
    {"wait", 0, "SDK read waiting, input resolution, timeout and closure passed"},
    {"wait_input_eof", 0, "SDK bounded result pipe, timeout and EOF wake passed"},
    {"wait_input_malformed", 0, "SDK bounded result pipe, timeout and malformed wake passed"},
    {"wait_input_partial", 0, "SDK bounded result pipe, timeout and partial wake passed"},
    {"wait_input_cancel", 0, "SDK bounded result pipe, timeout and cancellation wake passed"},
    {"wait_clock_probes", 0,
     "SDK clock probes, reserved output and result under stack lock passed"},
    {"wait_output_close", 0, "SDK blocked output, reserved control and closure wake passed"},
    {"wait_output_cancel", 0, "SDK blocked output, reserved control and cancellation wake passed"},
    {"wait_output_lost", 0, "SDK blocked output, reserved control and consumer loss wake passed"},
    {"writes", 0,
     [
       "SDK finite write scalar ownership and refusal passed",
       "SDK finite write admission, staged credit and deadline passed"
     ]},
    {"guard", 0,
     [
       "SDK attribute guard metadata, version, timing and current ACL passed",
       "SDK invoke guard metadata errors, timing and current ACL passed",
       "SDK invoke guard revocation, credential rollback and endpoint retirement passed",
       "SDK fabric scope attachment and shutdown passed"
     ]},
    {"guard_missing_finish", 70, "SDK fabric scope missing detach prepared"},
    {"requests_missing_finish", 70,
     [
       "bridge owned request metadata and arguments passed",
       "bridge request event loop responses passed"
     ]}
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
  @lifecycle_cases [
    {"normal", 0},
    {"advertised", 0},
    {"reopen", 0},
    {"reopen-missing", 70},
    {"window", 0},
    {"expiry", 0},
    {"closed", 0},
    {"busy", 0},
    {"interface", 0},
    {"store-exists", 0},
    {"store-locked", 0},
    {"preflight-allocation", 0},
    {"missing-finish", 70},
    {"running-finish", 70},
    {"unclosed-finish", 70}
  ]
  @lifecycle_exit_check """
  expected=$1
  duration=$2
  shift 2
  timeout "$duration" "$@"
  actual=$?
  printf '\\nbridge bootstrap exit: %s\\n' "$actual"
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
          [
            "ninja",
            "--quiet",
            "-C",
            "/work/" <> directory,
            "-j",
            "4",
            @target,
            @codec,
            @configuration,
            @bootstrap,
            @lifecycle
          ],
          []
        )

        configuration_output =
          inside.(
            directory <> "-configuration",
            ["/work/" <> directory <> "/" <> @configuration],
            @environment
          )

        verify_configuration!(configuration_output)

        bootstrap_output =
          inside.(
            directory <> "-bootstrap",
            ["/work/" <> directory <> "/" <> @bootstrap],
            @environment
          )

        verify_bootstrap!(bootstrap_output)

        lifecycle_cases =
          for {mode, expected} <- @lifecycle_cases do
            output =
              inside.(
                directory <> "-lifecycle-" <> mode,
                [
                  "/bin/sh",
                  "-c",
                  @lifecycle_exit_check,
                  "bridge-bootstrap-test",
                  Integer.to_string(expected),
                  if(mode == "expiry", do: "190", else: "20"),
                  "/work/" <> directory <> "/" <> @lifecycle,
                  mode
                ],
                @environment
              )

            verify_lifecycle!(output, expected)
            %{"mode" => mode, "exit_status" => expected}
          end

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

        result_path = Path.join([workspace, directory, "codec-results.ndjson"])
        generation = :binary.copy(<<255>>, 16)

        results =
          for outcome <- [:completed, :denied, :failed, :unknown], id <- [1, 0xFFFFFFFFFFFFFFFF] do
            {:ok, bytes} = Wotex.Matter.Bridge.Wire.encode_result(generation, id, outcome)
            bytes
          end

        File.write!(result_path, results)
        argument_path = Path.join([workspace, directory, "codec-arguments.ndjson"])
        File.write!(argument_path, argument_fixtures())
        probe_path = Path.join([workspace, directory, "codec-probes.ndjson"])
        File.write!(probe_path, probe_fixtures())

        codec_output =
          inside.(
            directory <> "-codec",
            [
              "/work/" <> directory <> "/" <> @codec,
              "/work/" <> directory <> "/codec-results.ndjson",
              "/work/" <> directory <> "/codec-arguments.ndjson",
              "/work/" <> directory <> "/codec-probes.ndjson"
            ],
            @environment
          )

        codec = verify_codec!(codec_output)

        codec =
          Map.merge(codec, %{
            "binary_sha256" => SoftwareManifest.digest(Path.join([workspace, directory, @codec])),
            "results_sha256" => SoftwareManifest.digest(result_path),
            "arguments_sha256" => SoftwareManifest.digest(argument_path),
            "probes_sha256" => SoftwareManifest.digest(probe_path)
          })

        {directory,
         %{
           "binary_sha256" => SoftwareManifest.digest(Path.join([workspace, directory, @target])),
           "generated_sha256" => compiled_model,
           "cases" => cases,
           "bootstrap" => %{
             "exit_status" => 0,
             "binary_sha256" =>
               SoftwareManifest.digest(Path.join([workspace, directory, @bootstrap]))
           },
           "lifecycle" => %{
             "binary_sha256" =>
               SoftwareManifest.digest(Path.join([workspace, directory, @lifecycle])),
             "cases" => lifecycle_cases
           },
           "configuration" => %{
             "exit_status" => 0,
             "binary_sha256" =>
               SoftwareManifest.digest(Path.join([workspace, directory, @configuration]))
           },
           "codec" => codec
         }}
      end

    %{
      "model_sha256" => SoftwareBridgeModel.profile()["model_sha256"],
      "generated_sha256" => SoftwareBridgeModel.profile()["generated_sha256"],
      "builds" => Map.new(builds)
    }
  end

  @doc false
  @spec verify_codec!(binary()) :: map()
  def verify_codec!(output) do
    unless String.ends_with?(
             output,
             "bridge paired request/result codec and allocation boundaries passed\n"
           ) and
             not Regex.match?(
               ~r/AddressSanitizer|LeakSanitizer|runtime error:|UndefinedBehaviorSanitizer/,
               output
             ),
           do: Mix.raise("bridge_codec_test_failed")

    generation = :binary.copy(<<255>>, 16)

    frames =
      for "bridge request fixture: " <> body <- String.split(output, "\n") do
        case Wotex.Matter.Bridge.Wire.decode_request(body <> "\n", generation) do
          {:ok, request} -> request
          _ -> Mix.raise("bridge_codec_test_failed")
        end
      end

    expected = [
      {:read, 6, 0, :case, nil},
      {:read, 6, 0, :group, nil},
      {:write, 3, 0, :case, {:u16, 65_535}},
      {:write, 6, 0x4001, :case, {:u16, 65_535}},
      {:write, 6, 0x4002, :case, {:u16, 65_535}},
      {:write, 6, 0x4003, :case, {:nullable_enum8, nil}},
      {:write, 6, 0x4003, :case, {:nullable_enum8, 0}},
      {:write, 6, 0x4003, :case, {:nullable_enum8, 1}},
      {:write, 6, 0x4003, :case, {:nullable_enum8, 2}},
      {:invoke, 6, 0, :case, {:tlv, 2}},
      {:invoke, 6, 0, :case, {:tlv, 65_536}},
      {:invoke, 6, 0, :case, {:tlv, 71}},
      {:invoke, 6, 0, :case, {:tlv, 8192}}
    ]

    actual =
      for frame <- frames do
        payload =
          case frame.payload do
            {:tlv, bytes} -> {:tlv, byte_size(bytes)}
            other -> other
          end

        {frame.operation, frame.path.cluster, frame.path.member, frame.principal.auth_mode, payload}
      end

    unless actual == expected and Enum.all?(frames, &fixture_metadata?/1) and
             Enum.count(String.split(output, "\n"), &(&1 == "bridge argument fixtures: 85 passed")) ==
               1,
           do: Mix.raise("bridge_codec_test_failed")

    verify_clock_samples!(output, generation)

    %{
      "request_fixtures" => length(frames),
      "result_frames" => 8,
      "argument_fixtures" => 85,
      "probe_frames" => 2,
      "clock_samples" => 2
    }
  end

  defp verify_clock_samples!(output, generation) do
    samples =
      for "bridge clock sample fixture: " <> frame <- String.split(output, "\n"), do: frame

    expected_samples = [{1, 0}, {0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF}]

    unless length(samples) == 2 and
             Enum.all?(Enum.zip(samples, expected_samples), fn {frame, {id, native_ms}} ->
               Wotex.Matter.Bridge.ClockProbe.decode(frame <> "\n", generation, id) ==
                 {:ok, native_ms}
             end) and
             Enum.count(String.split(output, "\n"), &(&1 == "bridge clock probe frames: 2 passed")) ==
               1,
           do: Mix.raise("bridge_codec_test_failed")
  end

  @spec probe_fixtures() :: iodata()
  def probe_fixtures do
    for id <- [1, 0xFFFFFFFFFFFFFFFF] do
      {:ok, frame} = Wotex.Matter.Bridge.ClockProbe.encode(:binary.copy(<<255>>, 16), id)
      frame
    end
  end

  @spec argument_fixtures() :: iodata()
  def argument_fixtures do
    tags = [
      {0, <<>>},
      {32, <<0>>},
      {64, <<0::little-16>>},
      {96, <<0::little-32>>},
      {128, <<0::little-16>>},
      {160, <<0::little-32>>},
      {192, <<0::little-48>>},
      {224, <<0::little-64>>}
    ]

    special =
      for {control, width} <- [{192, 16}, {224, 32}],
          number <- [0, 255, 256, 257],
          do: {control, <<0xFFFFFFFF::little-32, number::little-size(width)>>}

    tags = [{224, <<0xFFFFFFFFFFFFFFFF::little-64>>} | tags ++ special]

    for {control, tag} <- tags,
        bytes <- [
          <<control + 21>> <> tag <> <<24>>,
          <<21, control + 20>> <> tag <> <<24>>,
          <<21, 54, 0, control + 20>> <> tag <> <<24, 24>>,
          <<21, 55, 0, control + 20>> <> tag <> <<24, 24>>,
          <<21, control + 24>> <> tag
        ] do
      Jason.encode!(%{
        "bytes" => :binary.bin_to_list(bytes),
        "valid" => Wotex.Matter.Bridge.Arguments.valid?(bytes)
      }) <> "\n"
    end
  end

  defp fixture_metadata?(frame) do
    common = %{
      id: 0xFFFFFFFFFFFFFFFF,
      deadline_native_ms: 0xFFFFFFFFFFFFFFFF,
      generation: :binary.copy(<<255>>, 16),
      thing: <<0, 255>>,
      path: Map.put(frame.path, :endpoint, 3),
      principal: %{
        fabric_index: 254,
        auth_mode: frame.principal.auth_mode,
        subject: 0xFFFFFFFFFFFFFFFF,
        cats: [1, 0, 0xFFFFFFFF],
        is_commissioning: true
      },
      fabric_scope: %{
        epoch: 0xFFFFFFFFFFFFFFFF,
        fabric_id: 0xFFFFFFFFFFFFFFFF,
        bridge_node: 0xFFFFFFEFFFFFFFFF,
        root_public_key: <<4>> <> :binary.copy(<<255>>, 64),
        noc_sha256: :binary.copy(<<255>>, 32)
      },
      list: %{operation: :not_list, index: 0}
    }

    Map.take(frame, Map.keys(common)) == common and operation_metadata?(frame)
  end

  defp operation_metadata?(frame) do
    {version, flags} =
      case frame.operation do
        :read -> {nil, {true, false, true, true}}
        :write -> {0xFFFFFFFF, {true, true, false, false}}
        :invoke -> {nil, {false, true, false, false}}
      end

    {expanded, timed, filtered, large} = flags

    frame.data_version == version and
      frame.flags == %{
        expanded: expanded,
        timed: timed,
        fabric_filtered: filtered,
        allows_large_payload: large
      }
  end

  @spec verify_bootstrap!(binary()) :: :ok
  def verify_bootstrap!(output) do
    unless output == "owned SDK bootstrap credential loading passed\n",
      do: Mix.raise("bridge_bootstrap_test_failed")

    :ok
  end

  @spec verify_lifecycle!(binary(), integer()) :: :ok
  def verify_lifecycle!(output, expected) do
    receipt = if expected == 0, do: "owned SDK bootstrap resource lifecycle passed\n", else: ""

    unless expected in [0, 70] and
             output == receipt <> "\nbridge bootstrap exit: #{expected}\n",
           do: Mix.raise("bridge_lifecycle_test_failed")

    :ok
  end

  @spec verify_configuration!(binary()) :: :ok
  def verify_configuration!(output) do
    unless output == "bounded bridge bootstrap configuration passed\n",
      do: Mix.raise("bridge_configuration_test_failed")

    :ok
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
