defmodule Wotex.Profiles.CLITest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Profiles.{Artifacts, CLI, Contract, Draft, Validation, ValidationReport}
  alias Wotex.Profiles.Test.Fixtures, as: F

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "profile-cli-" <> Integer.to_string(System.unique_integer([:positive]))
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    {:ok, contract} =
      Contract.export(
        [F.json("installed-binding")],
        F.json("installed-contracts"),
        F.json("authoring-limits"),
        Artifacts.current()
      )

    {:ok, bytes} = Contract.encode(contract)
    File.write!(Path.join(directory, "contract.json"), bytes)
    {:ok, final} = Draft.finalize(F.bytes("authoring-draft"), contract)
    File.write!(Path.join(directory, "candidate.json"), final.bundle_bytes)
    File.write!(Path.join(directory, "draft.json"), F.bytes("authoring-draft"))
    File.write!(Path.join(directory, "capture.json"), F.bytes("capture"))
    {:ok, directory: directory, contract: contract, final: final}
  end

  defp arguments(directory),
    do: [
      "--contract",
      Path.join(directory, "contract.json"),
      "--candidate",
      Path.join(directory, "candidate.json")
    ]

  test "CLI reports are byte-identical to the public pure validator", context do
    args = arguments(context.directory)
    assert {0, bytes} = CLI.execute(:validate, args)
    assert {:ok, report} = Validation.check(context.final.bundle_bytes, context.contract, nil)
    assert {:ok, ^bytes} = ValidationReport.encode(report, context.contract)

    assert {0, bytes} =
             CLI.execute(
               :validate,
               args ++ ["--capture", Path.join(context.directory, "capture.json")]
             )

    assert Jason.decode!(bytes)["capture_status"] == "matched"
    File.write!(Path.join(context.directory, "candidate.json"), "{}")
    assert {1, _} = CLI.execute(:validate, args)
  end

  test "finalize writes only a successful derived bundle", context do
    output = Path.join(context.directory, "output.json")

    args = [
      "--contract",
      Path.join(context.directory, "contract.json"),
      "--candidate",
      Path.join(context.directory, "draft.json"),
      "--output",
      output
    ]

    assert {0, bytes} = CLI.execute(:finalize, args)
    assert File.read!(output) == context.final.bundle_bytes
    assert Jason.decode!(bytes)["bundle_sha256"] == context.final.bundle_sha256
    File.rm!(output)
    File.write!(Path.join(context.directory, "draft.json"), "{}")
    assert {1, _} = CLI.execute(:finalize, args)
    refute File.exists?(output)
  end

  test "argument, custody and resource failures expose no path or exception", context do
    for args <- [
          [],
          ["--unknown", "secret-canary"],
          arguments(context.directory) ++ ["--candidate", "secret-canary"],
          ["--contract", "secret-canary", "--candidate", "missing"],
          ["--contract"],
          ["--contract", "", "--candidate", "x"]
        ] do
      assert {2, bytes} = CLI.execute(:validate, args)
      refute bytes =~ "secret-canary"
      refute bytes =~ context.directory
    end

    File.write!(Path.join(context.directory, "candidate.json"), String.duplicate("x", 1_048_577))
    assert {2, bytes} = CLI.execute(:validate, arguments(context.directory))
    assert Jason.decode!(bytes) == %{"error" => %{"code" => "input_limit"}}
  end

  test "successful Mix task adapters render the same report and return normally", context do
    validate =
      ExUnit.CaptureIO.capture_io(fn ->
        assert :ok = Mix.Tasks.Wotex.Profiles.Validate.run(arguments(context.directory))
      end)

    assert Jason.decode!(validate)["disposition"] == "compatible"
    output = Path.join(context.directory, "mix-output.json")

    final =
      ExUnit.CaptureIO.capture_io(fn ->
        assert :ok =
                 Mix.Tasks.Wotex.Profiles.Finalize.run([
                   "--contract",
                   Path.join(context.directory, "contract.json"),
                   "--candidate",
                   Path.join(context.directory, "draft.json"),
                   "--output",
                   output
                 ])
      end)

    assert Jason.decode!(final)["bundle_sha256"] == context.final.bundle_sha256
    assert File.read!(output) == context.final.bundle_bytes
  end

  test "empty input, malformed capture and output custody failures are fixed failures", context do
    File.write!(Path.join(context.directory, "candidate.json"), "")
    assert {1, _} = CLI.execute(:validate, arguments(context.directory))
    File.write!(Path.join(context.directory, "candidate.json"), context.final.bundle_bytes)
    File.write!(Path.join(context.directory, "capture.json"), "{")

    assert {2, _} =
             CLI.execute(
               :validate,
               arguments(context.directory) ++
                 ["--capture", Path.join(context.directory, "capture.json")]
             )

    args = [
      "--contract",
      Path.join(context.directory, "contract.json"),
      "--candidate",
      Path.join(context.directory, "draft.json"),
      "--output",
      context.directory
    ]

    assert {2, _} = CLI.execute(:finalize, args)
    File.write!(Path.join(context.directory, "contract.json"), "{}")
    assert {2, _} = CLI.execute(:validate, arguments(context.directory))
  end
end
