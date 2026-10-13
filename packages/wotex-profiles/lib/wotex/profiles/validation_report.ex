defmodule Wotex.Profiles.ValidationReport do
  @moduledoc "Bounded deterministic authoring diagnostics tied to exact candidate and contract identities."

  alias Wotex.Profiles.{Contract, Envelope, Error, Grammar}

  @phases ~w(syntax shape semantic binding capture)
  @mechanics ~w(unsupported_schema unsupported_binding unsupported_selector unsupported_semantics codec_required)a
  @repairs ~w(edit_candidate supply_reference install_mechanic refresh_basis provide_capture)
  @codes ~w(invalid_input input_limit unsupported_format unsupported_schema reference_conflict missing_reference cyclic_reference unsupported_binding unsupported_selector unsupported_semantics fingerprint_mismatch inexact_conversion numeric_limit out_of_domain stale_basis codec_required invalid_contract report_limit)
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Returns checked safe diagnostics under their original supplied Contract."
  @spec to_map(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(%__MODULE__{data: data} = value, contract) when map_size(value) == 2 do
    with {:ok, contract} <- Contract.new(contract),
         {:ok, _} <- Envelope.admit(data),
         :ok <-
           Grammar.fields(
             data,
             ~w(format contract_sha256 candidate_sha256 disposition capture_status diagnostics truncated),
             "/report"
           ),
         true <-
           data["format"] == "wotex.profile.validation-report@1" and
             data["contract_sha256"] == contract.sha256,
         :ok <- Grammar.digest(data["candidate_sha256"], "/report"),
         true <-
           data["disposition"] in ~w(compatible invalid) and
             data["capture_status"] in ~w(not_supplied not_checked matched mismatch),
         true <- is_boolean(data["truncated"]) and is_list(data["diagnostics"]),
         true <- length(data["diagnostics"]) <= contract.data["limits"]["max_diagnostics"],
         :ok <- Grammar.each(data["diagnostics"], &diagnostic(&1, contract)),
         true <- ordered(data["diagnostics"]) == data["diagnostics"],
         true <- disposition?(data),
         {:ok, bytes} <- Envelope.encode(data),
         true <- byte_size(bytes) <= contract.data["limits"]["max_report_bytes"] do
      {:ok, data}
    else
      false -> Error.refusal(:invalid_input, "/report")
      error -> error
    end
  end

  def to_map(_, _), do: Error.refusal(:invalid_input, "/report")

  @doc "Returns canonical JSON only after report and Contract revalidation."
  @spec encode(term(), term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(value, contract) do
    with {:ok, data} <- to_map(value, contract), do: Envelope.encode(data)
  end

  @doc false
  @spec build(binary(), Contract.t(), String.t(), [map()], boolean()) ::
          {:ok, t()} | {:error, Error.t()}
  def build(bytes, contract, capture, diagnostics, truncated) do
    base = %{
      "format" => "wotex.profile.validation-report@1",
      "contract_sha256" => contract.sha256,
      "candidate_sha256" => Grammar.hash(bytes),
      "disposition" => if(diagnostics == [], do: "compatible", else: "invalid"),
      "capture_status" => capture,
      "diagnostics" => [],
      "truncated" => truncated
    }

    diagnostics = ordered(diagnostics)
    limits = contract.data["limits"]

    result =
      Enum.reduce_while(diagnostics, {base, 0}, fn diagnostic, {data, count} ->
        candidate = %{
          data
          | "diagnostics" => Enum.reverse([diagnostic | Enum.reverse(data["diagnostics"])])
        }

        {:ok, encoded} = Envelope.encode(candidate)

        if count < limits["max_diagnostics"] and byte_size(encoded) <= limits["max_report_bytes"],
          do: {:cont, {candidate, count + 1}},
          else: {:halt, {%{data | "truncated" => true}, count}}
      end)

    {data, count} = result
    {:ok, encoded} = Envelope.encode(data)

    if (diagnostics != [] and count == 0) or byte_size(encoded) > limits["max_report_bytes"],
      do: Error.refusal(:report_limit),
      else: {:ok, %__MODULE__{data: data}}
  end

  @doc false
  @spec failure(atom(), Error.t()) :: map()
  def failure(phase, error) do
    phase = Atom.to_string(phase)

    rule =
      cond do
        phase == "syntax" -> "SOURCE_SYNTAX"
        phase == "shape" -> "INPUT_SHAPE"
        phase == "binding" -> "INSTALLED_BINDING"
        phase == "capture" -> "CAPTURE_BASIS"
        error.code in [:missing_reference, :cyclic_reference] -> "DAG_CLOSURE"
        error.code == :reference_conflict -> "EXACT_REFERENCES"
        true -> "VALUE_GRAMMAR"
      end

    repair = repair(error.code, phase)

    %{
      "phase" => phase,
      "code" => Atom.to_string(error.code),
      "instance_path" => error.path,
      "rule_id" => rule,
      "repair" => repair
    }
  end

  defp repair(:missing_reference, _), do: "supply_reference"
  defp repair(:stale_basis, _), do: "refresh_basis"
  defp repair(_, "capture"), do: "provide_capture"

  defp repair(code, _) when code in @mechanics, do: "install_mechanic"

  defp repair(_, _), do: "edit_candidate"

  defp disposition?(%{"disposition" => "compatible", "diagnostics" => [], "truncated" => false}),
    do: true

  defp disposition?(%{"disposition" => "invalid", "diagnostics" => [_ | _]}), do: true
  defp disposition?(_), do: false

  defp diagnostic(data, contract) do
    with :ok <-
           Grammar.fields(data, ~w(phase code instance_path rule_id repair), "/report/diagnostics"),
         true <- data["phase"] in @phases and data["code"] in @codes and data["repair"] in @repairs,
         true <- data["rule_id"] in Enum.map(contract.data["semantic_rules"], & &1["id"]),
         true <- safe_pointer?(data["instance_path"], contract) do
      :ok
    else
      false -> Error.refusal(:invalid_input, "/report/diagnostics")
      error -> error
    end
  end

  defp safe_pointer?(path, contract) when is_binary(path) and byte_size(path) <= 512 do
    known =
      Enum.reduce(Map.values(contract.data["schemas"]), [], &names/2) ++
        ~w(closure bindings contracts capture fields digest sha256 limits checked projection fingerprint)

    path == "" or
      (String.starts_with?(path, "/") and
         Enum.all?(tl(String.split(path, "/")), fn segment ->
           segment in known or Regex.match?(~r/\A(?:0|[1-9][0-9]*)\z/, segment)
         end))
  end

  defp safe_pointer?(_, _), do: false

  defp names(schema, acc) when is_map(schema) do
    current = if is_map(schema["properties"]), do: Map.keys(schema["properties"]), else: []
    Enum.reduce(Map.values(schema), current ++ acc, &names/2)
  end

  defp names(schema, acc) when is_list(schema), do: Enum.reduce(schema, acc, &names/2)
  defp names(_, acc), do: acc

  defp ordered(values),
    do:
      Enum.sort_by(values, fn value ->
        {Enum.find_index(@phases, &(&1 == value["phase"])), pointer(value["instance_path"]),
         value["rule_id"], value["code"]}
      end)

  defp pointer(path),
    do:
      Enum.map(String.split(path, "/"), fn part ->
        case Integer.parse(part) do
          {integer, ""} -> {0, integer}
          _ -> {1, part}
        end
      end)
end
