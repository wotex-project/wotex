defmodule Wotex.Runtime.Implementation.Admission do
  @moduledoc """
  Pure, optional admission bound to exact deployment and consumer decisions.

  Revalidate with current `Wotex.Runtime.Implementation.Inputs` immediately
  before execution. A value proves neither artifact verification nor authority
  beyond the trusted decisions explicitly supplied by the consumer.
  """
  alias Wotex.Runtime.Implementation.{
    Descriptor,
    Error,
    Grammar,
    Inputs,
    JSON,
    Record,
    Registration
  }

  @type t :: %__MODULE__{
          value: map(),
          sha256: String.t(),
          descriptor: Descriptor.t(),
          registration: Registration.t()
        }
  defstruct [:value, :sha256, :descriptor, :registration]

  @doc "Checks grammar, registration, verification, trust and policy in that order."
  @spec new(term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def new(descriptor, inputs) do
    with {:ok, d} <- Record.validate(descriptor, Descriptor),
         {:ok, inputs} <- Inputs.validate(inputs),
         {:ok, registration} <- registration(descriptor, inputs),
         :ok <- compatibility(d, registration.value, inputs),
         :ok <- verification(descriptor, registration.value, inputs),
         :ok <- trust(descriptor, registration.value, inputs),
         :ok <- policy(descriptor, registration.value, inputs) do
      value = derived(descriptor, registration, inputs)
      {:ok, digest} = JSON.digest(value)

      {:ok,
       %__MODULE__{
         value: value,
         sha256: digest,
         descriptor: descriptor,
         registration: registration
       }}
    end
  end

  @doc "Reruns admission and rejects changed decisions, horizons or deployment identities."
  @spec revalidate(term(), term()) :: :ok | {:error, Error.t()}
  def revalidate(admission, inputs) do
    with :ok <- validate(admission),
         {:ok, current} <- new(admission.descriptor, inputs),
         true <-
           Map.delete(admission.value, "admitted_at_ms") ==
             Map.delete(current.value, "admitted_at_ms"),
         true <- inputs.now_ms >= admission.value["admitted_at_ms"] do
      :ok
    else
      {:error, _} = error -> error
      _ -> failure(:stale_admission, :execution)
    end
  end

  @doc false
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(%__MODULE__{} = admission) do
    with true <-
           Grammar.closed?(Map.from_struct(admission), [:value, :sha256, :descriptor, :registration]),
         {:ok, d} <- Record.validate(admission.descriptor, Descriptor),
         {:ok, r} <- Record.validate(admission.registration, Registration),
         {:ok, digest} <- JSON.digest(admission.value),
         true <-
           Grammar.closed?(
             admission.value,
             ~w(schema scope target descriptor_sha256 registration_sha256 deployment verification_sha256 trust_sha256 policy_sha256 permissions limits valid_until_ms admitted_at_ms)
           ),
         true <- admission.value["schema"] == "wotex.implementation-admission@1",
         true <- admission.sha256 == digest,
         true <-
           admission.value["descriptor_sha256"] == admission.descriptor.sha256 and
             admission.value["registration_sha256"] == admission.registration.sha256 and
             r["descriptor_sha256"] == admission.descriptor.sha256 and r["id"] == d["id"] and
             admission.value["deployment"] == r["deployment"] and
             admission.value["permissions"] == d["permissions"],
         true <-
           Enum.all?(~w(scope target), &Grammar.token?(admission.value[&1])) and
             Enum.all?(~w(trust_sha256 policy_sha256), &Grammar.digest?(admission.value[&1])) and
             valid_verification_digest?(d, admission.value["verification_sha256"]) and
             Grammar.limits?(admission.value["limits"]) and
             Grammar.horizon?(admission.value["valid_until_ms"]) and
             Grammar.time?(admission.value["admitted_at_ms"]),
         true <-
           Enum.all?(admission.value["limits"], fn {key, value} ->
             value <= d["limits"][key] and value <= r["limits"][key]
           end) do
      :ok
    else
      _ -> failure(:invalid_admission_inputs, :construction)
    end
  end

  def validate(_), do: failure(:invalid_admission_inputs, :construction)

  defp registration(descriptor, inputs) do
    case Map.fetch(inputs.registrations, descriptor.value["id"]) do
      {:ok, registration} ->
        if registration.value["descriptor_sha256"] == descriptor.sha256 and
             registration.value["kind"] == descriptor.value["kind"],
           do: {:ok, registration},
           else: failure(:identity_mismatch, :compatibility)

      :error ->
        failure(:registration_missing, :compatibility)
    end
  end

  defp compatibility(d, r, inputs) do
    cond do
      not compatible_tuple?(d["api"], r["apis"]) or not compatible_tuple?(d["api"], inputs.apis) ->
        failure(:incompatible_api, :compatibility)

      not compatible_tuple?(d["binding"], r["bindings"]) or
          not compatible_tuple?(d["binding"], inputs.bindings) ->
        failure(:incompatible_binding, :compatibility)

      d["configuration_schema"] != r["configuration_schema"] or d["state"] != r["state"] ->
        failure(:identity_mismatch, :compatibility)

      not Grammar.subset?(d["support"], r["support"]) ->
        failure(:unsupported_cell, :compatibility)

      not Grammar.subset?(d["requires"], r["requires"]) ->
        failure(:unsupported_requirement, :compatibility)

      not Grammar.grants?(d["permissions"], r["permissions"]) ->
        failure(:permission_denied, :compatibility)

      true ->
        :ok
    end
  end

  defp compatible_tuple?(tuple, available),
    do:
      Enum.any?(available, fn candidate ->
        tuple["id"] == candidate["id"] and
          Grammar.compatible?(tuple["version"], candidate["version"])
      end)

  defp verification(%{value: %{"artifact" => nil}}, r, _) do
    if r["deployment"]["kind"] in ~w(beam_release data),
      do: :ok,
      else: failure(:identity_mismatch, :verification)
  end

  defp verification(descriptor, r, inputs) do
    artifact = descriptor.value["artifact"]
    receipt = if inputs.verification, do: inputs.verification.value, else: nil

    cond do
      artifact["target"] != inputs.target ->
        failure(:target_mismatch, :verification)

      is_nil(receipt) ->
        failure(:artifact_unverified, :verification)

      receipt["descriptor_sha256"] != descriptor.sha256 or receipt["artifact"] != artifact ->
        failure(:identity_mismatch, :verification)

      r["deployment"] != %{"kind" => "native_payload", "identity" => artifact["payload_identity"]} ->
        failure(:identity_mismatch, :verification)

      receipt["verified_at_ms"] > inputs.now_ms ->
        failure(:artifact_unverified, :verification)

      not guarantees?(r["enforcement"], ~w(immutable_deployment)) ->
        failure(:deployment_mutable, :verification)

      true ->
        :ok
    end
  end

  defp trust(descriptor, r, inputs) do
    trust = inputs.trust.value

    cond do
      trust["scope"] != inputs.scope or trust["descriptor_sha256"] != descriptor.sha256 or
          trust["deployment"] != r["deployment"] ->
        failure(:identity_mismatch, :trust)

      expired?(trust["valid_until_ms"], inputs.now_ms) ->
        failure(:trust_expired, :trust)

      true ->
        :ok
    end
  end

  defp policy(descriptor, r, inputs) do
    p = inputs.policy.value
    native? = descriptor.value["artifact"] != nil

    exception =
      if inputs.verification, do: inputs.verification.value["security_exception"], else: nil

    cond do
      not policy_identity?(p, descriptor, r, inputs) ->
        failure(:identity_mismatch, :policy)

      expired?(p["valid_until_ms"], inputs.now_ms) ->
        failure(:stale_admission, :policy)

      p["security_status"] == "denied" or invalid_exception?(exception, inputs) ->
        failure(:security_denied, :policy)

      not Grammar.grants?(descriptor.value["permissions"], p["grants"]) ->
        failure(:permission_denied, :policy)

      true ->
        policy_enforcement(descriptor.value, r, p, native?)
    end
  end

  defp policy_identity?(p, descriptor, r, inputs) do
    p["scope"] == inputs.scope and p["target"] == inputs.target and
      p["descriptor_sha256"] == descriptor.sha256 and p["deployment"] == r["deployment"]
  end

  defp policy_enforcement(d, r, p, native?) do
    cond do
      not enforcement?(r["enforcement"], p["enforcement"], native?) ->
        failure(:enforcement_unavailable, :policy)

      native? and not guarantees?(p["enforcement"], ~w(immutable_deployment)) ->
        failure(:deployment_mutable, :policy)

      native? and
          Enum.any?(
            ~w(startup_ms request_ms shutdown_ms inflight frame_bytes queue_bytes memory_bytes),
            &(min(d["limits"][&1], min(r["limits"][&1], p["limits"][&1])) == 0)
          ) ->
        failure(:enforcement_unavailable, :policy)

      true ->
        :ok
    end
  end

  defp enforcement?(registered, policy, native?) do
    registered["id"] == policy["id"] and registered["trust"] == "trusted" and
      policy["trust"] == "trusted" and
      Grammar.subset?(policy["guarantees"], registered["guarantees"]) and
      (native? or not Enum.any?(policy["guarantees"], &(&1 in ~w(memory privileges descendants))))
  end

  defp guarantees?(enforcement, guarantees),
    do: Grammar.subset?(guarantees, enforcement["guarantees"])

  defp invalid_exception?(nil, _), do: false

  defp invalid_exception?(exception, inputs),
    do: expired?(exception["expires_at_ms"], inputs.now_ms) or exception["scope"] != inputs.scope

  defp expired?(nil, _), do: false
  defp expired?(horizon, now), do: now >= horizon

  defp derived(descriptor, registration, inputs) do
    d = descriptor.value
    p = inputs.policy.value
    trust = inputs.trust.value
    horizons = Enum.reject([p["valid_until_ms"], trust["valid_until_ms"]], &is_nil/1)

    %{
      "schema" => "wotex.implementation-admission@1",
      "scope" => inputs.scope,
      "target" => inputs.target,
      "descriptor_sha256" => descriptor.sha256,
      "registration_sha256" => registration.sha256,
      "deployment" => registration.value["deployment"],
      "verification_sha256" => if(d["artifact"], do: inputs.verification.sha256, else: nil),
      "trust_sha256" => inputs.trust.sha256,
      "policy_sha256" => inputs.policy.sha256,
      "permissions" => d["permissions"],
      "limits" =>
        Map.new(d["limits"], fn {key, ceiling} ->
          {key, min(ceiling, min(registration.value["limits"][key], p["limits"][key]))}
        end),
      "valid_until_ms" => if(horizons == [], do: nil, else: Enum.min(horizons)),
      "admitted_at_ms" => inputs.now_ms
    }
  end

  defp valid_verification_digest?(%{"artifact" => nil}, digest), do: is_nil(digest)
  defp valid_verification_digest?(_, digest), do: Grammar.digest?(digest)
  defp failure(code, phase), do: {:error, Error.new(code, phase, %{})}
end
