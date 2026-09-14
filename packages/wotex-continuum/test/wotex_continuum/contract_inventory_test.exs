defmodule WotexContinuum.ContractInventoryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias WotexContinuum.{
    ActionIntent,
    ActionResult,
    Artifact,
    CanonicalJSON,
    Capability,
    CapabilityRequirement,
    Codec,
    Compatibility,
    Degradation,
    Delivery,
    Error,
    EvidenceReference,
    ExecutionScope,
    ExitReceipt,
    Failure,
    Lifecycle,
    Manifest,
    Mode,
    ObservationProposal
  }

  @vectors Path.expand("../vectors", __DIR__)

  @contracts %{
    "action_intent" => %{
      module: ActionIntent,
      required: ~w(intent_id thing_id action_name input requested_at idempotency_key context)a,
      defaults: %{requested_by: nil, evidence: [], extensions: %{}},
      null_errors: %{
        requested_by: :invalid_type,
        evidence: :invalid_type,
        extensions: :invalid_type
      },
      forge: :intent_id
    },
    "action_result" => %{
      module: ActionResult,
      required: ~w(result_id intent_id status context)a,
      defaults: %{
        output: nil,
        error: nil,
        started_at: nil,
        completed_at: nil,
        evidence: [],
        extensions: %{}
      },
      null_errors: %{
        error: :invalid_type,
        started_at: :invalid_type,
        completed_at: :invalid_type,
        evidence: :invalid_type,
        extensions: :invalid_type
      },
      forge: :result_id
    },
    "capability" => %{
      module: Capability,
      required: ~w(id version operations modes network degradation)a,
      defaults: %{extensions: %{}},
      null_errors: %{extensions: :invalid_type},
      forge: :id
    },
    "compatibility" => %{
      module: Compatibility,
      required: ~w(schema_requirement)a,
      defaults: %{required_capabilities: [], extensions: %{}},
      null_errors: %{required_capabilities: :invalid_type, extensions: :invalid_type},
      forge: :schema_requirement
    },
    "continuum_manifest" => %{
      module: Manifest,
      required: ~w(manifest_id artifact compatibility supported_modes capabilities)a,
      defaults: %{extensions: %{}},
      null_errors: %{extensions: :invalid_type},
      forge: :manifest_id
    },
    "degradation" => %{
      module: Degradation,
      required: ~w(degradation_id subject_id level capabilities reason_codes since recoverable)a,
      defaults: %{evidence: [], extensions: %{}},
      null_errors: %{evidence: :invalid_type, extensions: :invalid_type},
      forge: :degradation_id
    },
    "delivery" => %{
      module: Delivery,
      required: ~w(delivery_id item_kind item_id source destination status attempt emitted_at)a,
      defaults: %{sequence: nil, acknowledged_at: nil, error: nil, extensions: %{}},
      null_errors: %{
        sequence: :invalid_integer,
        acknowledged_at: :invalid_type,
        error: :invalid_type,
        extensions: :invalid_type
      },
      forge: :delivery_id
    },
    "evidence_reference" => %{
      module: EvidenceReference,
      required: ~w(evidence_id uri digest media_type captured_at)a,
      defaults: %{extensions: %{}},
      null_errors: %{extensions: :invalid_type},
      forge: :evidence_id
    },
    "execution_scope" => %{
      module: ExecutionScope,
      required: ~w(execution_id node_id mode observed_at)a,
      defaults: %{extensions: %{}},
      null_errors: %{extensions: :invalid_type},
      forge: :execution_id
    },
    "exit_receipt" => %{
      module: ExitReceipt,
      required: ~w(receipt_id subject_id operation status requested_at)a,
      defaults: %{completed_at: nil, artifacts: [], residuals: [], error: nil, extensions: %{}},
      null_errors: %{
        completed_at: :invalid_type,
        artifacts: :invalid_type,
        residuals: :invalid_type,
        error: :invalid_type,
        extensions: :invalid_type
      },
      forge: :receipt_id
    },
    "lifecycle" => %{
      module: Lifecycle,
      required: ~w(subject_id state generation changed_at)a,
      defaults: %{reason: nil, extensions: %{}},
      null_errors: %{reason: :invalid_type, extensions: :invalid_type},
      forge: :subject_id
    },
    "mode" => %{
      module: Mode,
      required: ~w(deployment connectivity)a,
      defaults: %{extensions: %{}},
      null_errors: %{extensions: :invalid_type},
      forge: :deployment
    },
    "observation_proposal" => %{
      module: ObservationProposal,
      required: ~w(proposal_id thing_id affordance_type affordance_name value observed_at context)a,
      defaults: %{sequence: nil, quality: %{}, evidence: [], extensions: %{}},
      null_errors: %{
        sequence: :invalid_integer,
        quality: :invalid_type,
        evidence: :invalid_type,
        extensions: :invalid_type
      },
      forge: :proposal_id
    }
  }

  test "field inventory covers every registered struct member and constructor route" do
    assert Enum.sort(Map.keys(@contracts)) == WotexContinuum.kinds()

    for {kind, contract} <- @contracts do
      input = valid_input(kind)
      module = contract.module

      fields =
        module.__struct__()
        |> Map.from_struct()
        |> Map.keys()
        |> List.delete(:output_present?)
        |> Enum.sort()

      inventory = Enum.sort(contract.required ++ Map.keys(contract.defaults))
      assert fields == inventory, "incomplete field inventory for #{kind}"

      assert {:ok, value} = module.from_map(input), kind
      assert {:ok, ^value} = module.new(input), kind
      assert {:ok, ^value} = WotexContinuum.from_map(input), kind

      unknown = Map.put(input, "ambient_policy", true)

      assert_contract_error(module.from_map(unknown), :unknown_field, "/ambient_policy", kind)
      assert_contract_error(module.new(unknown), :unknown_field, "/ambient_policy", kind)

      assert_contract_error(
        WotexContinuum.from_map(unknown),
        :unknown_field,
        "/ambient_policy",
        kind
      )
    end
  end

  test "every required field has exact map and forged-struct rejection evidence" do
    for {kind, contract} <- @contracts do
      input = valid_input(kind)
      module = contract.module

      for field <- contract.required do
        invalid = Map.delete(input, Atom.to_string(field))
        path = "/#{field}"

        assert_contract_error(module.from_map(invalid), :required, path, kind)
        assert_contract_error(module.new(invalid), :required, path, kind)
        assert_contract_error(WotexContinuum.from_map(invalid), :required, path, kind)
      end

      assert {:ok, value} = module.from_map(input), kind
      field = contract.forge
      path = "/#{field}"
      equivalent_map = Map.put(input, Atom.to_string(field), nil)
      forged = Map.put(value, field, nil)

      assert {:error, %Error{} = map_error} = module.from_map(equivalent_map), kind
      assert map_error.phase == :validation, kind
      assert map_error.path == path, kind
      struct_error = assert_contract_error(module.from_map(forged), map_error.code, path, kind)

      assert Map.take(struct_error, [:code, :phase, :path]) ==
               Map.take(map_error, [:code, :phase, :path])

      assert_contract_error(module.new(forged), map_error.code, path, kind)
      assert_contract_error(WotexContinuum.to_map(forged), map_error.code, path, kind)
      assert_contract_error(Codec.encode(forged), map_error.code, path, kind)
    end
  end

  test "omission applies every documented constructor default" do
    for {kind, contract} <- @contracts do
      module = contract.module

      input =
        kind
        |> valid_input()
        |> nonterminal_variant(kind)
        |> Map.drop(Enum.map(Map.keys(contract.defaults), &Atom.to_string/1))

      assert {:ok, value} = module.from_map(input), kind
      wire = module.to_map(value)

      for {field, expected} <- contract.defaults do
        assert Map.fetch!(value, field) == expected, "wrong #{kind}.#{field} default"

        if is_nil(expected) do
          refute Map.has_key?(wire, Atom.to_string(field)), "#{kind}.#{field} should stay absent"
        else
          assert Map.fetch!(wire, Atom.to_string(field)) == expected,
                 "wrong projected #{kind}.#{field} default"
        end
      end

      if kind == "action_result", do: refute(value.output_present?)
    end
  end

  test "explicit null is distinct from omission for typed optional fields" do
    for {kind, contract} <- @contracts,
        {field, code} <- contract.null_errors do
      input = Map.put(valid_input(kind), Atom.to_string(field), nil)
      assert_contract_error(contract.module.from_map(input), code, "/#{field}", kind)
    end

    for {kind, field} <- [
          {"action_intent", "input"},
          {"action_result", "output"},
          {"observation_proposal", "value"}
        ] do
      module = @contracts[kind].module
      assert {:ok, value} = module.from_map(Map.put(valid_input(kind), field, nil)), kind
      assert Map.fetch!(module.to_map(value), field) == nil
    end

    assert {:ok, failure} = Failure.from_map(%{code: "rejected", message: "example", details: nil})
    assert Failure.to_map(failure)["details"] == nil
  end

  test "native constructors default envelopes while encoded values require complete wire identity" do
    for {kind, contract} <- @contracts do
      module = contract.module
      input = valid_input(kind)
      native = Map.drop(input, ["kind", "schema_version"])

      assert {:ok, value} = module.from_map(native), kind
      assert {:ok, ^value} = module.new(native), kind
      assert module.to_map(value)["kind"] == kind
      assert module.to_map(value)["schema_version"] == WotexContinuum.schema_version()

      for field <- ["kind", "schema_version"] do
        encoded =
          input
          |> Map.delete(field)
          |> Jason.encode!()

        assert_contract_error(Codec.decode(encoded), :required, "/#{field}", kind)
      end
    end
  end

  test "nested contracts have valid, invalid, canonical, closed, and reconstructed evidence" do
    digest = "sha256:" <> String.duplicate("a", 64)

    nested = [
      {Artifact, %{name: "example", version: "1.0.0", digest: digest}, ~w(name version digest)a,
       ~s({"digest":"#{digest}","name":"example","version":"1.0.0"})},
      {CapabilityRequirement, %{id: "buffering", version_requirement: "~> 1.0"},
       ~w(id version_requirement)a, ~s({"id":"buffering","version_requirement":"~> 1.0"})},
      {Failure, %{code: "rejected", message: "example", details: %{"retryable" => false}},
       ~w(code message)a, ~s({"code":"rejected","details":{"retryable":false},"message":"example"})}
    ]

    for {module, input, required, canonical} <- nested do
      assert {:ok, value} = module.from_map(input)
      assert {:ok, ^value} = module.new(input)
      assert {:ok, ^value} = module.from_map(value)
      assert {:ok, ^canonical} = CanonicalJSON.encode(module.to_map(value))

      unknown = Map.put(input, :ambient_policy, true)

      assert_contract_error(
        module.from_map(unknown),
        :unknown_field,
        "/ambient_policy",
        inspect(module)
      )

      assert_contract_error(module.new(unknown), :unknown_field, "/ambient_policy", inspect(module))

      for field <- required do
        assert_contract_error(
          module.from_map(Map.delete(input, field)),
          :required,
          "/#{field}",
          inspect(module)
        )
      end

      field = hd(required)

      map_error =
        assert_contract_error(
          module.from_map(Map.put(input, field, nil)),
          :invalid_type,
          "/#{field}",
          inspect(module)
        )

      struct_error =
        assert_contract_error(
          module.from_map(Map.put(value, field, nil)),
          :invalid_type,
          "/#{field}",
          inspect(module)
        )

      assert Map.take(struct_error, [:code, :phase, :path]) ==
               Map.take(map_error, [:code, :phase, :path])
    end

    assert {:ok, failure} = Failure.from_map(%{code: "rejected", message: "example"})
    assert failure.details == %{}
    assert Failure.to_map(failure)["details"] == %{}
  end

  test "nested unknown fields remain closed through their owning top-level constructors" do
    manifest = valid_input("continuum_manifest")

    assert_contract_error(
      manifest
      |> put_in(["artifact", "ambient_policy"], true)
      |> WotexContinuum.from_map(),
      :unknown_field,
      "/artifact/ambient_policy",
      "artifact"
    )

    requirement = get_in(manifest, ["compatibility", "required_capabilities", Access.at(0)])

    assert_contract_error(
      manifest
      |> put_in(
        ["compatibility", "required_capabilities", Access.at(0)],
        Map.put(requirement, "ambient_policy", true)
      )
      |> WotexContinuum.from_map(),
      :unknown_field,
      "/compatibility/required_capabilities/0/ambient_policy",
      "capability requirement"
    )

    result =
      "action_result"
      |> valid_input()
      |> Map.put("status", "failed")
      |> Map.delete("output")
      |> Map.put("error", %{
        "code" => "rejected",
        "message" => "example",
        "ambient_policy" => true
      })

    assert_contract_error(
      WotexContinuum.from_map(result),
      :unknown_field,
      "/error/ambient_policy",
      "failure"
    )
  end

  defp valid_input(kind) do
    [@vectors, "valid", "*.json"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.find_value(fn path ->
      input =
        path
        |> File.read!()
        |> Jason.decode!()

      if input["kind"] == kind, do: input
    end)
  end

  defp nonterminal_variant(input, "action_result"), do: Map.put(input, "status", "accepted")
  defp nonterminal_variant(input, "delivery"), do: Map.put(input, "status", "pending")
  defp nonterminal_variant(input, "exit_receipt"), do: Map.put(input, "status", "requested")
  defp nonterminal_variant(input, _), do: input

  defp assert_contract_error(result, code, path, label) do
    assert {:error, %Error{} = error} = result, label
    assert error.code == code, label
    assert error.phase == :validation, label
    assert error.path == path, label
    error
  end
end
