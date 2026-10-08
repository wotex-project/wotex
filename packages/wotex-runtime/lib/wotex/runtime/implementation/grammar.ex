defmodule Wotex.Runtime.Implementation.Grammar do
  @moduledoc false

  @safe 9_007_199_254_740_991
  @limits %{
    "startup_ms" => 60_000,
    "request_ms" => 60_000,
    "shutdown_ms" => 10_000,
    "inflight" => 32,
    "queued" => 64,
    "frame_bytes" => 131_072,
    "queue_bytes" => 1_048_576,
    "stderr_bytes" => 8192,
    "memory_bytes" => 1_073_741_824
  }
  @kinds ~w(data_mapping beam_adapter codec native_host)
  @operations Enum.map(Wotex.Runtime.operations(), &Atom.to_string/1)

  @doc false
  @spec closed?(term(), [term()]) :: boolean()
  def closed?(value, keys),
    do:
      is_map(value) and not is_struct(value) and map_size(value) == length(keys) and
        Enum.all?(keys, &Map.has_key?(value, &1))

  @doc false
  @spec token?(term()) :: boolean()
  def token?(value), do: matches?(value, 128, ~r/\A[a-z0-9][a-z0-9._:\/-]*\z/)
  @doc false
  @spec id?(term()) :: boolean()
  def id?(value), do: matches?(value, 128, ~r/\A[a-z0-9][a-z0-9._-]*\z/)
  @doc false
  @spec digest?(term()) :: boolean()
  def digest?(value), do: matches?(value, 64, ~r/\A[0-9a-f]{64}\z/)
  @doc false
  @spec text?(term(), pos_integer()) :: boolean()
  def text?(value, max),
    do: is_binary(value) and byte_size(value) in 1..max and String.valid?(value)

  @doc false
  @spec time?(term()) :: boolean()
  def time?(value), do: is_integer(value) and value >= 0 and value <= @safe
  @doc false
  @spec horizon?(term()) :: boolean()
  def horizon?(nil), do: true
  def horizon?(value), do: time?(value)
  @doc false
  @spec version?(term()) :: boolean()
  def version?(value) do
    if matches?(
         value,
         64,
         ~r/\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z/
       ) do
      value
      |> String.split("+", parts: 2)
      |> hd()
      |> String.split("-", parts: 2)
      |> valid_prerelease?()
    else
      false
    end
  end

  @doc false
  @spec compatible?(String.t(), String.t()) :: boolean()
  def compatible?(wanted, host) do
    wanted = hd(String.split(wanted, "+", parts: 2))
    host = hd(String.split(host, "+", parts: 2))
    [major, minor | _] = String.split(wanted, ".")
    [host_major, host_minor | _] = String.split(host, ".")

    if major == "0" or String.contains?(wanted, "-") or String.contains?(host, "-"),
      do: wanted == host,
      else: major == host_major and minor == host_minor
  end

  @doc false
  @spec tuple?(term()) :: boolean()
  def tuple?(value),
    do: closed?(value, ~w(id version)) and token?(value["id"]) and version?(value["version"])

  @doc false
  @spec tuples?(term()) :: boolean()
  def tuples?(value), do: distinct?(value, 8, &tuple?/1, 1)
  @doc false
  @spec schema_ref?(term()) :: boolean()
  def schema_ref?(value),
    do: closed?(value, ~w(id sha256)) and token?(value["id"]) and digest?(value["sha256"])

  @doc false
  @spec artifact?(term()) :: boolean()
  def artifact?(value) do
    closed?(value, ~w(package profile target build_identity payload_identity)) and
      Enum.all?(~w(package profile target), &token?(value[&1])) and
      Enum.all?(~w(build_identity payload_identity), &digest?(value[&1]))
  end

  @doc false
  @spec deployment?(term()) :: boolean()
  def deployment?(value) do
    closed?(value, ~w(kind identity)) and
      case value["kind"] do
        kind when kind in ~w(beam_release native_payload) -> digest?(value["identity"])
        "data" -> text?(value["identity"], 256)
        _ -> false
      end
  end

  @doc false
  @spec support?(term()) :: boolean()
  def support?(value), do: distinct?(value, 64, &cell?/1)
  @doc false
  @spec requires?(term()) :: boolean()
  def requires?(value), do: distinct?(value, 32, &token?/1)
  @doc false
  @spec permissions?(term()) :: boolean()
  def permissions?(value), do: distinct?(value, 32, &permission?/1)
  @doc false
  @spec state?(term()) :: boolean()
  def state?(value) do
    closed?(value, ~w(scope continuity update_mode format)) and
      value["scope"] in ~w(stateless consumer_instance) and
      value["continuity"] in ~w(none explicit_loss) and
      value["update_mode"] in ~w(message_boundary stop_reopen) and
      (is_nil(value["format"]) or token?(value["format"]))
  end

  @doc false
  @spec limits?(term()) :: boolean()
  def limits?(value) do
    closed?(value, Map.keys(@limits)) and
      Enum.all?(@limits, fn {key, max} ->
        is_integer(value[key]) and value[key] >= 0 and value[key] <= max
      end)
  end

  @doc false
  @spec enforcement?(term()) :: boolean()
  def enforcement?(value) do
    closed?(value, ~w(id trust guarantees)) and token?(value["id"]) and
      value["trust"] in ~w(trusted untrusted) and
      distinct?(
        value["guarantees"],
        5,
        &(&1 in ~w(memory deadline descendants privileges immutable_deployment))
      )
  end

  @doc false
  @spec codec_contract?(term()) :: boolean()
  def codec_contract?(value),
    do:
      closed?(value, ~w(id version sha256)) and
        token?(value["id"]) and version?(value["version"]) and digest?(value["sha256"])

  @doc false
  @spec descriptor?(term()) :: boolean()
  def descriptor?(value) do
    closed?(
      value,
      ~w(schema id version kind api binding artifact entrypoint support requires configuration_schema permissions state limits extensions)
    ) and
      value["schema"] == "wotex.implementation@1" and id?(value["id"]) and
      version?(value["version"]) and value["kind"] in @kinds and
      tuple?(value["api"]) and tuple?(value["binding"]) and
      shared_contract?(value) and extensions?(value["extensions"]) and
      artifact_entrypoint?(value) and kind_consistent?(value) and nonnegative?(value)
  end

  @doc false
  @spec registration?(term()) :: boolean()
  def registration?(value) do
    closed?(
      value,
      ~w(schema id kind descriptor_sha256 deployment apis bindings support requires permissions configuration_schema state enforcement limits codec_contract)
    ) and
      value["schema"] == "wotex.implementation-registration@1" and id?(value["id"]) and
      value["kind"] in @kinds and digest?(value["descriptor_sha256"]) and
      deployment?(value["deployment"]) and tuples?(value["apis"]) and tuples?(value["bindings"]) and
      shared_contract?(value) and enforcement?(value["enforcement"]) and
      registration_kind?(value) and registered_codec?(value)
  end

  defp registered_codec?(%{"kind" => "codec"} = value), do: codec_contract?(value["codec_contract"])
  defp registered_codec?(value), do: is_nil(value["codec_contract"])

  defp shared_contract?(value) do
    schema_ref?(value["configuration_schema"]) and support?(value["support"]) and
      requires?(value["requires"]) and permissions?(value["permissions"]) and
      state?(value["state"]) and limits?(value["limits"])
  end

  @doc false
  @spec verification?(term()) :: boolean()
  def verification?(value) do
    closed?(
      value,
      ~w(schema descriptor_sha256 artifact native_descriptor_schema payload_manifest_schema artifact_format closure_sha256 deployment_evidence_sha256 legal_sha256 sbom_sha256 advisory_receipt_sha256 security_exception verified_at_ms verifier_id verifier_revision)
    ) and
      value["schema"] == "wotex.implementation-verification@1" and
      artifact?(value["artifact"]) and
      value["native_descriptor_schema"] == "wotex.native-artifact-descriptor@2" and
      value["payload_manifest_schema"] == "wotex.native-payload-manifest@1" and
      value["artifact_format"] == "wotex.native-artifact@1" and
      Enum.all?(
        ~w(descriptor_sha256 closure_sha256 deployment_evidence_sha256 legal_sha256 sbom_sha256 advisory_receipt_sha256),
        &digest?(value[&1])
      ) and
      time?(value["verified_at_ms"]) and token?(value["verifier_id"]) and
      token?(value["verifier_revision"]) and
      exception?(value["security_exception"], value["artifact"])
  end

  @doc false
  @spec trust?(term()) :: boolean()
  def trust?(value) do
    closed?(
      value,
      ~w(schema mode approval_id scope descriptor_sha256 deployment revision valid_until_ms update)
    ) and
      value["schema"] == "wotex.implementation-trust@1" and
      value["mode"] in ~w(local_pin verified_update) and
      Enum.all?(~w(approval_id scope revision), &token?(value[&1])) and
      digest?(value["descriptor_sha256"]) and deployment?(value["deployment"]) and
      horizon?(value["valid_until_ms"]) and trust_mode?(value)
  end

  @doc false
  @spec policy?(term()) :: boolean()
  def policy?(value) do
    closed?(
      value,
      ~w(schema scope target descriptor_sha256 deployment revision valid_until_ms grants limits enforcement security_status security_revision)
    ) and
      value["schema"] == "wotex.implementation-policy@1" and
      Enum.all?(~w(scope target revision security_revision), &token?(value[&1])) and
      digest?(value["descriptor_sha256"]) and deployment?(value["deployment"]) and
      horizon?(value["valid_until_ms"]) and permissions?(value["grants"]) and
      limits?(value["limits"]) and enforcement?(value["enforcement"]) and
      value["security_status"] in ~w(allowed denied)
  end

  @doc false
  @spec distinct?(term(), non_neg_integer(), (term() -> boolean()), non_neg_integer()) :: boolean()
  def distinct?(value, max, predicate, min \\ 0) do
    case bounded_list(value, max, predicate, %{}, 0) do
      {:ok, count} -> count >= min
      :error -> false
    end
  end

  defp bounded_list([], _, _, _, count), do: {:ok, count}

  defp bounded_list([value | rest], max, predicate, seen, count) when count < max do
    if predicate.(value) and not is_map_key(seen, value),
      do: bounded_list(rest, max, predicate, Map.put(seen, value, true), count + 1),
      else: :error
  end

  defp bounded_list(_, _, _, _, _), do: :error

  @doc false
  @spec grants?(list(), list()) :: boolean()
  def grants?(requests, grants) do
    Enum.all?(requests, fn request ->
      Enum.any?(grants, fn grant ->
        request["kind"] == grant["kind"] and request["resource"] == grant["resource"] and
          subset?(request["operations"], grant["operations"])
      end)
    end)
  end

  @doc false
  @spec subset?(list(), list()) :: boolean()
  def subset?(requested, available), do: Enum.all?(requested, &(&1 in available))

  defp matches?(value, max, pattern), do: text?(value, max) and Regex.match?(pattern, value)
  defp valid_prerelease?([_]), do: true

  defp valid_prerelease?([_, pre]),
    do:
      Enum.all?(String.split(pre, "."), fn part ->
        not Regex.match?(~r/\A[0-9]+\z/, part) or part == "0" or not String.starts_with?(part, "0")
      end)

  defp cell?(value) do
    closed?(value, ~w(direction scheme operation media_type security_scheme)) and
      value["direction"] in ~w(consumed exposed) and value["operation"] in @operations and
      matches?(value["scheme"], 32, ~r/\A[a-z][a-z0-9+.-]*\z/) and
      matches?(value["media_type"], 128, ~r/\A[a-z0-9!#$&^_.+-]+\/[a-z0-9!#$&^_.+-]+\z/) and
      token?(value["security_scheme"])
  end

  defp permission?(value) do
    closed?(value, ~w(kind resource operations)) and
      value["kind"] in ~w(network device service store credential) and
      token?(value["resource"]) and distinct?(value["operations"], 16, &token?/1, 1)
  end

  defp extensions?(value) do
    is_map(value) and not is_struct(value) and map_size(value) <= 16 and
      Enum.all?(Map.keys(value), fn key ->
        token?(key) and
          case String.split(key, ":", parts: 2) do
            [namespace, name] -> namespace != "" and name != ""
            _ -> false
          end
      end)
  end

  defp artifact_entrypoint?(%{
         "artifact" => nil,
         "entrypoint" => nil,
         "kind" => kind,
         "binding" => binding
       }),
       do:
         kind in ~w(data_mapping beam_adapter) or
           (kind == "codec" and binding["id"] == "beam-codec")

  defp artifact_entrypoint?(value),
    do:
      artifact?(value["artifact"]) and path?(value["entrypoint"]) and
        (value["kind"] == "native_host" or
           (value["kind"] == "codec" and value["binding"]["id"] == "process-codec")) and
        Enum.all?(
          ~w(startup_ms request_ms shutdown_ms inflight frame_bytes queue_bytes memory_bytes),
          &(value["limits"][&1] > 0)
        )

  defp path?(value) do
    text?(value, 256) and not String.contains?(value, "\\") and
      not Regex.match?(~r/[\x00-\x1f\x7f]/, value) and
      case String.split(value, "/") do
        components when length(components) <= 16 ->
          Enum.all?(components, &(&1 not in ["", ".", ".."]))

        _ ->
          false
      end
  end

  defp kind_consistent?(value) do
    case value["kind"] do
      kind when kind in ~w(data_mapping codec) ->
        value["permissions"] == [] and (kind != "data_mapping" or value["support"] == []) and
          value["state"] == %{
            "scope" => "stateless",
            "continuity" => "none",
            "update_mode" => "message_boundary",
            "format" => nil
          }

      "native_host" ->
        native_state?(value)

      "beam_adapter" ->
        value["support"] != []
    end
  end

  defp native_state?(value),
    do:
      value["support"] != [] and
        value["state"]["scope"] == "consumer_instance" and
        value["state"]["continuity"] == "explicit_loss" and
        value["state"]["update_mode"] == "stop_reopen" and
        (not Enum.any?(value["permissions"], &(&1["kind"] == "store")) or
           token?(value["state"]["format"]))

  defp registration_kind?(value) do
    kind_consistent?(value) and
      case value["kind"] do
        "data_mapping" -> value["deployment"]["kind"] == "data"
        "beam_adapter" -> value["deployment"]["kind"] == "beam_release"
        "native_host" -> value["deployment"]["kind"] == "native_payload"
        "codec" -> value["deployment"]["kind"] in ~w(beam_release native_payload)
      end
  end

  defp exception?(nil, _), do: true

  defp exception?(value, artifact) do
    closed?(value, ~w(id payload_identity scope expires_at_ms decision_sha256)) and
      token?(value["id"]) and token?(value["scope"]) and time?(value["expires_at_ms"]) and
      digest?(value["decision_sha256"]) and
      value["payload_identity"] == artifact["payload_identity"]
  end

  defp trust_mode?(%{"mode" => "local_pin", "update" => nil}), do: true

  defp trust_mode?(%{"mode" => "verified_update", "update" => update, "valid_until_ms" => horizon}) do
    update?(update) and time?(horizon) and horizon <= update["expires_at_ms"]
  end

  defp trust_mode?(_), do: false

  defp update?(value) do
    closed?(
      value,
      ~w(verifier_profile verifier_revision root_revision signature_receipt_sha256 metadata_versions high_water_versions threshold_required verified_signers expires_at_ms revocation_revision rollback_checked)
    ) and
      Enum.all?(
        ~w(verifier_profile verifier_revision root_revision revocation_revision),
        &token?(value[&1])
      ) and
      digest?(value["signature_receipt_sha256"]) and time?(value["expires_at_ms"]) and
      versions?(value["metadata_versions"]) and versions?(value["high_water_versions"]) and
      Map.keys(value["metadata_versions"]) |> Enum.sort() ==
        Enum.sort(Map.keys(value["high_water_versions"])) and
      signers?(value) and
      value["rollback_checked"] == true and
      Enum.all?(value["metadata_versions"], fn {role, version} ->
        version >= value["high_water_versions"][role]
      end)
  end

  defp signers?(value) do
    is_integer(value["threshold_required"]) and value["threshold_required"] in 1..32 and
      distinct?(value["verified_signers"], 32, &token?/1, 1) and
      length(value["verified_signers"]) >= value["threshold_required"]
  end

  defp versions?(value),
    do:
      is_map(value) and not is_struct(value) and map_size(value) in 1..32 and
        Enum.all?(value, fn {role, version} -> token?(role) and time?(version) and version > 0 end)

  defp nonnegative?(value) when is_integer(value), do: value >= 0

  defp nonnegative?(value) when is_map(value),
    do: Enum.all?(value, fn {_, child} -> nonnegative?(child) end)

  defp nonnegative?(value) when is_list(value), do: Enum.all?(value, &nonnegative?/1)
  defp nonnegative?(_), do: true
end
