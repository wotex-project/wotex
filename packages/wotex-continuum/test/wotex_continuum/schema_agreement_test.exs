defmodule WotexContinuum.SchemaAgreementTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias WotexContinuum.{Codec, Error, JSONSchemaSubset, Schema}

  @vectors Path.expand("../../priv/vectors", __DIR__)

  @document_for_kind %{
    "capability" => "wct-01.schema.json",
    "compatibility" => "wct-01.schema.json",
    "continuum_manifest" => "wct-01.schema.json",
    "execution_scope" => "wct-01.schema.json",
    "action_intent" => "wct-02.schema.json",
    "action_result" => "wct-02.schema.json",
    "delivery" => "wct-02.schema.json",
    "evidence_reference" => "wct-02.schema.json",
    "observation_proposal" => "wct-02.schema.json",
    "degradation" => "wct-03.schema.json",
    "exit_receipt" => "wct-03.schema.json",
    "lifecycle" => "wct-03.schema.json",
    "mode" => "wct-03.schema.json"
  }

  @optional_fields %{
    "action_intent" => ~w(requested_by evidence extensions),
    "action_result" => ~w(started_at evidence extensions),
    "capability" => ~w(extensions),
    "compatibility" => ~w(required_capabilities extensions),
    "continuum_manifest" => ~w(extensions),
    "degradation" => ~w(evidence extensions),
    "delivery" => ~w(sequence extensions),
    "evidence_reference" => ~w(extensions),
    "execution_scope" => ~w(extensions),
    "exit_receipt" => ~w(artifacts residuals extensions),
    "lifecycle" => ~w(reason extensions),
    "mode" => ~w(extensions),
    "observation_proposal" => ~w(sequence quality evidence extensions)
  }

  @required_fields %{
    "action_intent" =>
      ~w(intent_id thing_id action_name input requested_at idempotency_key context),
    "action_result" => ~w(result_id intent_id status context),
    "capability" => ~w(id version operations modes network degradation),
    "compatibility" => ~w(schema_requirement),
    "continuum_manifest" => ~w(manifest_id artifact compatibility supported_modes capabilities),
    "degradation" =>
      ~w(degradation_id subject_id level capabilities reason_codes since recoverable),
    "delivery" => ~w(delivery_id item_kind item_id source destination status attempt emitted_at),
    "evidence_reference" => ~w(evidence_id uri digest media_type captured_at),
    "execution_scope" => ~w(execution_id node_id mode observed_at),
    "exit_receipt" => ~w(receipt_id subject_id operation status requested_at),
    "lifecycle" => ~w(subject_id state generation changed_at),
    "mode" => ~w(deployment connectivity),
    "observation_proposal" =>
      ~w(proposal_id thing_id affordance_type affordance_name value observed_at context)
  }

  @format_fields %{
    "action_intent" => [
      {~w(thing_id), :invalid_iri},
      {~w(requested_at), :invalid_timestamp},
      {~w(context observed_at), :invalid_timestamp}
    ],
    "action_result" => [
      {~w(started_at), :invalid_timestamp},
      {~w(completed_at), :invalid_timestamp},
      {~w(context observed_at), :invalid_timestamp}
    ],
    "degradation" => [{~w(since), :invalid_timestamp}],
    "delivery" => [
      {~w(emitted_at), :invalid_timestamp},
      {~w(acknowledged_at), :invalid_timestamp}
    ],
    "evidence_reference" => [
      {~w(uri), :invalid_iri},
      {~w(captured_at), :invalid_timestamp}
    ],
    "execution_scope" => [{~w(observed_at), :invalid_timestamp}],
    "exit_receipt" => [
      {~w(requested_at), :invalid_timestamp},
      {~w(completed_at), :invalid_timestamp}
    ],
    "lifecycle" => [{~w(changed_at), :invalid_timestamp}],
    "observation_proposal" => [
      {~w(thing_id), :invalid_iri},
      {~w(observed_at), :invalid_timestamp},
      {~w(context observed_at), :invalid_timestamp}
    ]
  }

  test "every registered kind agrees across schema, construction, reconstruction, and codecs" do
    registry = registry()
    valid = inputs_by_kind("valid")
    canonical = inputs_by_kind("canonical")

    assert Enum.sort(Map.keys(valid)) == WotexContinuum.kinds()
    assert Enum.sort(Map.keys(canonical)) == WotexContinuum.kinds()

    for kind <- WotexContinuum.kinds() do
      input = Map.fetch!(valid, kind)
      module = module!(kind)
      document = document_for(kind)

      assert :ok = JSONSchemaSubset.validate(input, document, registry), kind
      assert {:ok, value} = module.from_map(input), kind
      assert {:ok, ^value} = module.new(input), kind
      assert {:ok, ^value} = module.from_map(value), kind
      assert {:ok, ^value} = module.new(value), kind
      assert {:ok, ^value} = WotexContinuum.from_map(input), kind

      projected = module.to_map(value)
      assert projected == input, kind
      assert :ok = JSONSchemaSubset.validate(projected, document, registry), kind
      assert {:ok, ^projected} = WotexContinuum.to_map(value), kind

      assert {:ok, ^value} = Codec.decode(Jason.encode!(input)), kind
      assert {:ok, encoded} = Codec.encode(value), kind
      assert {:ok, ^value} = Codec.decode(encoded), kind
      assert {:ok, stable_bytes} = Codec.canonicalize(value), kind
      assert {:ok, ^value} = Codec.decode(stable_bytes), kind

      native = Map.drop(input, ["kind", "schema_version"])
      assert {:ok, native_value} = module.from_map(native), kind
      assert {:ok, ^native_value} = module.new(native), kind
      assert module.to_map(native_value) == input, kind

      vector = Map.fetch!(canonical, kind)
      canonical_input = vector["input"]
      assert :ok = JSONSchemaSubset.validate(canonical_input, document, registry), kind
      assert {:ok, canonical_value} = WotexContinuum.from_map(canonical_input), kind
      assert {:ok, canonical_bytes} = Codec.canonicalize(canonical_value), kind
      assert canonical_bytes == vector["canonical"], kind
      assert {:ok, ^canonical_value} = Codec.decode(canonical_bytes), kind
    end
  end

  test "schema and codec admit every documented omission default" do
    registry = registry()

    for {kind, fields} <- @optional_fields do
      input = Map.drop(valid_input(kind), fields)
      document = document_for(kind)

      assert :ok = JSONSchemaSubset.validate(input, document, registry), kind
      assert {:ok, value} = Codec.decode(Jason.encode!(input)), kind
      assert {:ok, projected} = WotexContinuum.to_map(value), kind
      assert :ok = JSONSchemaSubset.validate(projected, document, registry), kind
    end
  end

  test "required and closed-field rules agree for every registered kind" do
    registry = registry()

    for {kind, fields} <- @required_fields do
      module = module!(kind)
      document = document_for(kind)

      for field <- fields do
        input = Map.delete(valid_input(kind), field)
        path = "/#{field}"
        label = "#{kind} #{path}"

        assert {:error, [_ | _]} = JSONSchemaSubset.validate(input, document, registry), label
        assert_error(module.from_map(input), :required, path, label)
        assert_error(module.new(input), :required, path, label)
        assert_error(WotexContinuum.from_map(input), :required, path, label)
        assert_error(Codec.decode(Jason.encode!(input)), :required, path, label)
      end

      unknown = Map.put(valid_input(kind), "ambient_policy", true)
      label = "#{kind} unknown member"
      assert {:error, [_ | _]} = JSONSchemaSubset.validate(unknown, document, registry), label
      assert_error(module.from_map(unknown), :unknown_field, "/ambient_policy", label)
      assert_error(WotexContinuum.from_map(unknown), :unknown_field, "/ambient_policy", label)
      assert_error(Codec.decode(Jason.encode!(unknown)), :unknown_field, "/ambient_policy", label)
    end
  end

  test "schema-expressible state matrices equal constructor admission" do
    registry = registry()

    for {label, kind, input} <- state_matrix_cases() do
      schema_ok? = JSONSchemaSubset.validate(input, document_for(kind), registry) == :ok
      constructor_ok? = match?({:ok, _}, module!(kind).from_map(input))

      assert schema_ok? == constructor_ok?, label
    end
  end

  test "schema version is exact for every registered kind and route" do
    registry = registry()

    for kind <- WotexContinuum.kinds() do
      input = Map.put(valid_input(kind), "schema_version", "2.0.1")
      module = module!(kind)

      assert {:error, [_ | _]} =
               JSONSchemaSubset.validate(input, document_for(kind), registry),
             kind

      assert_error(
        module.from_map(input),
        :unsupported_schema_version,
        "/schema_version",
        kind,
        :compatibility
      )

      assert_error(
        module.new(input),
        :unsupported_schema_version,
        "/schema_version",
        kind,
        :compatibility
      )

      assert_error(
        WotexContinuum.from_map(input),
        :unsupported_schema_version,
        "/schema_version",
        kind,
        :compatibility
      )

      assert_error(
        Codec.decode(Jason.encode!(input)),
        :unsupported_schema_version,
        "/schema_version",
        kind,
        :compatibility
      )
    end
  end

  test "format assertions agree with constructors at every registered field path" do
    registry = registry()

    for {kind, fields} <- @format_fields,
        {segments, code} <- fields do
      input = put_path(valid_input(kind), segments, "not a valid value")
      path = "/" <> Enum.join(segments, "/")
      label = "#{kind} #{path}"

      assert {:error, [_ | _]} =
               JSONSchemaSubset.validate(input, document_for(kind), registry),
             label

      assert_error(module!(kind).from_map(input), code, path, label)
      assert_error(WotexContinuum.from_map(input), code, path, label)
      assert_error(Codec.decode(Jason.encode!(input)), code, path, label)
    end
  end

  test "propertyNames assertions agree for every registered extensions owner" do
    registry = registry()

    for kind <- WotexContinuum.kinds() do
      input = Map.put(valid_input(kind), "extensions", %{"relative-extension" => true})
      module = module!(kind)

      assert {:error, [_ | _]} =
               JSONSchemaSubset.validate(input, document_for(kind), registry),
             kind

      assert_error(module.from_map(input), :invalid_iri, "/extensions", kind)
      assert_error(WotexContinuum.from_map(input), :invalid_iri, "/extensions", kind)
      assert_error(Codec.decode(Jason.encode!(input)), :invalid_iri, "/extensions", kind)

      assert {:ok, value} = module.from_map(valid_input(kind)), kind
      forged = Map.put(value, :extensions, %{"relative-extension" => true})
      assert_error(module.from_map(forged), :invalid_iri, "/extensions", kind)
      assert_error(WotexContinuum.to_map(forged), :invalid_iri, "/extensions", kind)
      assert_error(Codec.encode(forged), :invalid_iri, "/extensions", kind)
      assert_error(Codec.canonicalize(forged), :invalid_iri, "/extensions", kind)
    end
  end

  test "every published invalid kind keeps exact errors across constructor routes" do
    paths = Path.wildcard(Path.join([@vectors, "invalid", "*.json"]))

    covered_kinds =
      paths
      |> Enum.map(&read_json(&1)["input"]["kind"])
      |> Enum.uniq()
      |> Enum.sort()

    assert covered_kinds == WotexContinuum.kinds()

    for path <- paths do
      vector = read_json(path)
      input = vector["input"]
      expected = vector["expected"]
      kind = input["kind"]
      module = module!(kind)

      code = String.to_existing_atom(expected["code"])
      phase = String.to_existing_atom(expected["phase"])

      assert_error(module.from_map(input), code, expected["path"], path, phase)
      assert_error(module.new(input), code, expected["path"], path, phase)
      assert_error(WotexContinuum.from_map(input), code, expected["path"], path, phase)
      assert_error(Codec.decode(Jason.encode!(input)), code, expected["path"], path, phase)
    end
  end

  test "nested values reject the same invalid field at every owning-parent path" do
    registry = registry()

    for {label, kind, input, child_path, field} <- invalid_parent_cases() do
      path = pointer(append_segment(child_path, field))
      invalid = update_path(input, child_path, &Map.put(&1, field, []))
      module = module!(kind)

      assert {:error, [_ | _]} =
               JSONSchemaSubset.validate(invalid, document_for(kind), registry),
             label

      assert_error(module.from_map(invalid), :invalid_type, path, label)
      assert_error(module.new(invalid), :invalid_type, path, label)
      assert_error(WotexContinuum.from_map(invalid), :invalid_type, path, label)
      assert_error(Codec.decode(Jason.encode!(invalid)), :invalid_type, path, label)

      assert {:ok, value} = module.from_map(input), label

      forged =
        update_struct_path(value, child_path, &Map.put(&1, String.to_existing_atom(field), []))

      assert_error(module.from_map(forged), :invalid_type, path, label)
      assert_error(module.new(forged), :invalid_type, path, label)
      assert_error(WotexContinuum.to_map(forged), :invalid_type, path, label)
      assert_error(Codec.encode(forged), :invalid_type, path, label)
      assert_error(Codec.canonicalize(forged), :invalid_type, path, label)
    end
  end

  test "nested registered envelopes default only below the top-level boundary" do
    registry = registry()

    for {label, kind, input, child_path} <- registered_parent_cases() do
      module = module!(kind)

      without_nested_envelope =
        update_path(input, child_path, &Map.drop(&1, ["kind", "schema_version"]))

      assert :ok =
               JSONSchemaSubset.validate(
                 without_nested_envelope,
                 document_for(kind),
                 registry
               ),
             label

      assert {:ok, value} = module.from_map(without_nested_envelope), label
      assert {:ok, ^value} = module.new(without_nested_envelope), label
      assert {:ok, ^value} = WotexContinuum.from_map(without_nested_envelope), label
      assert {:ok, ^value} = Codec.decode(Jason.encode!(without_nested_envelope)), label

      assert {:ok, projected} = WotexContinuum.to_map(value), label
      assert get_path(projected, child_path)["kind"], label
      assert get_path(projected, child_path)["schema_version"] == "2.0.0", label
      assert :ok = JSONSchemaSubset.validate(projected, document_for(kind), registry), label

      for {field, invalid_value, code, phase} <- [
            {"kind", "wrong_kind", :wrong_kind, :validation},
            {"schema_version", "2.0.1", :unsupported_schema_version, :compatibility}
          ] do
        invalid = update_path(input, child_path, &Map.put(&1, field, invalid_value))
        path = pointer(append_segment(child_path, field))
        mismatch_label = "#{label} #{field}"

        assert {:error, [_ | _]} =
                 JSONSchemaSubset.validate(invalid, document_for(kind), registry),
               mismatch_label

        assert_error(module.from_map(invalid), code, path, mismatch_label, phase)
        assert_error(WotexContinuum.from_map(invalid), code, path, mismatch_label, phase)
        assert_error(Codec.decode(Jason.encode!(invalid)), code, path, mismatch_label, phase)
      end
    end
  end

  test "nested extension property names are checked through every registered owner" do
    registry = registry()

    for {label, kind, input, child_path} <- registered_parent_cases() do
      path = pointer(append_segment(child_path, "extensions"))
      module = module!(kind)

      invalid =
        update_path(input, child_path, fn child ->
          Map.put(child, "extensions", %{"relative-extension" => true})
        end)

      assert {:error, [_ | _]} =
               JSONSchemaSubset.validate(invalid, document_for(kind), registry),
             label

      assert_error(module.from_map(invalid), :invalid_iri, path, label)
      assert_error(WotexContinuum.from_map(invalid), :invalid_iri, path, label)
      assert_error(Codec.decode(Jason.encode!(invalid)), :invalid_iri, path, label)

      assert {:ok, value} = module.from_map(input), label

      forged =
        update_struct_path(value, child_path, fn child ->
          Map.put(child, :extensions, %{"relative-extension" => true})
        end)

      assert_error(module.from_map(forged), :invalid_iri, path, label)
      assert_error(WotexContinuum.to_map(forged), :invalid_iri, path, label)
      assert_error(Codec.encode(forged), :invalid_iri, path, label)
      assert_error(Codec.canonicalize(forged), :invalid_iri, path, label)
    end
  end

  test "optional failure details agree through every failure owner" do
    registry = registry()

    for {label, kind, input} <- failure_parent_cases() do
      module = module!(kind)
      assert :ok = JSONSchemaSubset.validate(input, document_for(kind), registry), label
      assert {:ok, value} = module.from_map(input), label
      assert {:ok, ^value} = module.new(input), label
      assert {:ok, ^value} = Codec.decode(Jason.encode!(input)), label
      assert {:ok, projected} = WotexContinuum.to_map(value), label
      assert get_in(projected, ["error", "details"]) == %{}, label
      assert :ok = JSONSchemaSubset.validate(projected, document_for(kind), registry), label
    end
  end

  defp registry do
    Enum.reduce(
      %{
        "WCT.01" => "wct-01.schema.json",
        "WCT.02" => "wct-02.schema.json",
        "WCT.03" => "wct-03.schema.json"
      },
      %{},
      fn {id, file}, registry ->
        assert {:ok, source} = Schema.fetch(id)
        schema = Jason.decode!(source)

        registry
        |> Map.put(file, schema)
        |> Map.put(schema["$id"], schema)
      end
    )
  end

  defp inputs_by_kind(directory) do
    [@vectors, directory, "*.json"]
    |> Path.join()
    |> Path.wildcard()
    |> Map.new(fn path ->
      vector = read_json(path)
      input = if directory == "canonical", do: vector["input"], else: vector
      {input["kind"], if(directory == "canonical", do: vector, else: input)}
    end)
  end

  defp valid_input(kind), do: Map.fetch!(inputs_by_kind("valid"), kind)
  defp document_for(kind), do: Map.fetch!(@document_for_kind, kind)

  defp module!(kind) do
    {:ok, module} = WotexContinuum.module_for_kind(kind)
    module
  end

  defp read_json(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  defp invalid_parent_cases do
    manifest = valid_input("continuum_manifest")
    compatibility = compatibility_with_requirement()
    observation = with_evidence(valid_input("observation_proposal"))
    intent = with_evidence(valid_input("action_intent"))
    result = with_evidence(valid_input("action_result"))
    degradation = with_evidence(valid_input("degradation"))
    exit = with_artifact(valid_input("exit_receipt"))

    [
      {"manifest artifact", "continuum_manifest", manifest, ~w(artifact), "name"},
      {"manifest compatibility", "continuum_manifest", manifest, ~w(compatibility),
       "schema_requirement"},
      {"manifest capability", "continuum_manifest", manifest, ["capabilities", 0], "id"},
      {"manifest capability requirement", "continuum_manifest", manifest,
       ["compatibility", "required_capabilities", 0], "id"},
      {"compatibility requirement", "compatibility", compatibility, ["required_capabilities", 0],
       "id"},
      {"execution scope mode", "execution_scope", valid_input("execution_scope"), ~w(mode),
       "deployment"},
      {"observation evidence", "observation_proposal", observation, ["evidence", 0], "evidence_id"},
      {"observation context", "observation_proposal", observation, ~w(context), "execution_id"},
      {"observation context mode", "observation_proposal", observation, ~w(context mode),
       "deployment"},
      {"Action intent evidence", "action_intent", intent, ["evidence", 0], "evidence_id"},
      {"Action intent context", "action_intent", intent, ~w(context), "execution_id"},
      {"Action intent context mode", "action_intent", intent, ~w(context mode), "deployment"},
      {"Action result evidence", "action_result", result, ["evidence", 0], "evidence_id"},
      {"Action result context", "action_result", result, ~w(context), "execution_id"},
      {"Action result context mode", "action_result", result, ~w(context mode), "deployment"},
      {"Action result failure", "action_result", failed_result(), ~w(error), "code"},
      {"delivery failure", "delivery", failed_delivery(), ~w(error), "code"},
      {"degradation evidence", "degradation", degradation, ["evidence", 0], "evidence_id"},
      {"exit artifact", "exit_receipt", exit, ["artifacts", 0], "evidence_id"},
      {"exit failure", "exit_receipt", failed_exit(), ~w(error), "code"}
    ]
  end

  defp registered_parent_cases do
    manifest = valid_input("continuum_manifest")
    observation = with_evidence(valid_input("observation_proposal"))
    intent = with_evidence(valid_input("action_intent"))
    result = with_evidence(valid_input("action_result"))
    degradation = with_evidence(valid_input("degradation"))
    exit = with_artifact(valid_input("exit_receipt"))

    [
      {"manifest compatibility", "continuum_manifest", manifest, ~w(compatibility)},
      {"manifest capability", "continuum_manifest", manifest, ["capabilities", 0]},
      {"execution scope mode", "execution_scope", valid_input("execution_scope"), ~w(mode)},
      {"observation evidence", "observation_proposal", observation, ["evidence", 0]},
      {"observation context", "observation_proposal", observation, ~w(context)},
      {"observation context mode", "observation_proposal", observation, ~w(context mode)},
      {"Action intent evidence", "action_intent", intent, ["evidence", 0]},
      {"Action intent context", "action_intent", intent, ~w(context)},
      {"Action intent context mode", "action_intent", intent, ~w(context mode)},
      {"Action result evidence", "action_result", result, ["evidence", 0]},
      {"Action result context", "action_result", result, ~w(context)},
      {"Action result context mode", "action_result", result, ~w(context mode)},
      {"degradation evidence", "degradation", degradation, ["evidence", 0]},
      {"exit artifact", "exit_receipt", exit, ["artifacts", 0]}
    ]
  end

  defp failure_parent_cases do
    [
      {"Action result failure", "action_result", failed_result()},
      {"delivery failure", "delivery", failed_delivery()},
      {"exit failure", "exit_receipt", failed_exit()}
    ]
  end

  defp compatibility_with_requirement do
    valid_input("compatibility")
    |> Map.put("required_capabilities", [
      %{"id" => "example-capability", "version_requirement" => "~> 1.0"}
    ])
  end

  defp with_evidence(input), do: Map.put(input, "evidence", [valid_input("evidence_reference")])
  defp with_artifact(input), do: Map.put(input, "artifacts", [valid_input("evidence_reference")])

  defp failed_result do
    valid_input("action_result")
    |> Map.put("status", "failed")
    |> Map.delete("output")
    |> Map.put("error", failure())
  end

  defp failed_delivery do
    valid_input("delivery")
    |> Map.put("status", "failed")
    |> Map.delete("acknowledged_at")
    |> Map.put("error", failure())
  end

  defp failed_exit do
    valid_input("exit_receipt")
    |> Map.put("status", "failed")
    |> Map.put("error", failure())
  end

  defp failure, do: %{"code" => "rejected", "message" => "example"}

  defp state_matrix_cases do
    action_result_cases() ++
      delivery_cases() ++ degradation_cases() ++ exit_cases() ++ mode_cases()
  end

  defp action_result_cases do
    base = Map.drop(valid_input("action_result"), ["output", "error", "completed_at"])

    for status <- ~w(accepted running succeeded failed cancelled unknown),
        output? <- [false, true],
        error? <- [false, true],
        completed? <- [false, true] do
      input =
        base
        |> Map.put("status", status)
        |> maybe_put("output", nil, output?)
        |> maybe_put("error", failure(), error?)
        |> maybe_put("completed_at", "2026-09-02T10:00:04Z", completed?)

      {"action_result #{status} output=#{output?} error=#{error?} completed=#{completed?}",
       "action_result", input}
    end
  end

  defp delivery_cases do
    base = Map.drop(valid_input("delivery"), ["acknowledged_at", "error"])

    for status <- ~w(pending in_flight delivered acknowledged failed unknown),
        acknowledged? <- [false, true],
        error? <- [false, true] do
      input =
        base
        |> Map.put("status", status)
        |> maybe_put("acknowledged_at", "2026-09-02T10:00:06Z", acknowledged?)
        |> maybe_put("error", failure(), error?)

      {"delivery #{status} acknowledged=#{acknowledged?} error=#{error?}", "delivery", input}
    end
  end

  defp degradation_cases do
    base = valid_input("degradation")

    for level <- ~w(none reduced unavailable),
        capabilities? <- [false, true],
        reasons? <- [false, true] do
      input =
        base
        |> Map.put("level", level)
        |> Map.put("capabilities", if(capabilities?, do: ["example-capability"], else: []))
        |> Map.put("reason_codes", if(reasons?, do: ["example-reason"], else: []))

      {"degradation #{level} capabilities=#{capabilities?} reasons=#{reasons?}", "degradation",
       input}
    end
  end

  defp exit_cases do
    base = Map.drop(valid_input("exit_receipt"), ["completed_at", "residuals", "error"])

    for operation <- ~w(export remove),
        status <- ~w(requested running completed failed partial),
        completed? <- [false, true],
        residuals? <- [false, true],
        error? <- [false, true] do
      input =
        base
        |> Map.put("operation", operation)
        |> Map.put("status", status)
        |> maybe_put("completed_at", "2026-09-02T10:00:09Z", completed?)
        |> Map.put("residuals", if(residuals?, do: ["example-residual"], else: []))
        |> maybe_put("error", failure(), error?)

      {"exit #{operation} #{status} completed=#{completed?} residuals=#{residuals?} error=#{error?}",
       "exit_receipt", input}
    end
  end

  defp mode_cases do
    for deployment <- ~w(saas hybrid connected_onprem air_gapped),
        connectivity <- ~w(connected intermittent disconnected) do
      input =
        valid_input("mode")
        |> Map.put("deployment", deployment)
        |> Map.put("connectivity", connectivity)

      {"mode #{deployment} #{connectivity}", "mode", input}
    end
  end

  defp maybe_put(map, _, _, false), do: map
  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)

  defp put_path(map, [key], value), do: Map.put(map, key, value)

  defp put_path(map, [key | rest], value) do
    Map.update!(map, key, &put_path(&1, rest, value))
  end

  defp update_path(value, path, update) do
    update_in(value, Enum.map(path, &access/1), update)
  end

  defp get_path(value, path), do: get_in(value, Enum.map(path, &access/1))

  defp update_struct_path(value, path, update) do
    update_in(value, Enum.map(path, &struct_access/1), update)
  end

  defp access(index) when is_integer(index), do: Access.at(index)
  defp access(key), do: Access.key!(key)

  defp struct_access(index) when is_integer(index), do: Access.at(index)
  defp struct_access(key), do: Access.key!(String.to_existing_atom(key))

  defp pointer(segments), do: "/" <> Enum.map_join(segments, "/", &to_string/1)

  defp append_segment(segments, segment), do: Enum.reverse([segment | Enum.reverse(segments)])

  defp assert_error(result, code, path, label, phase \\ :validation) do
    assert {:error, %Error{} = error} = result, label
    assert error.code == code, label
    assert error.phase == phase, label
    assert error.path == path, label
    assert String.valid?(error.path), label
  end
end
