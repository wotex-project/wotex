defmodule Wotex.Profiles.Contract do
  @moduledoc """
  Installed authoring grammar and explicit consumer binding, contract and limit selections.

  Contract integrity is separate from trust, source/model correctness and current
  consumer admission. Export, parse and native reuse compare the exact installed
  artifact set before any candidate schema execution.
  """

  alias Wotex.Profiles.{Artifacts, AuthoringLimits, Binding, Envelope, Error, Grammar, Limits}

  @fields ~w(format producer schemas semantic_rules bindings contracts limits)
  @enforce_keys [:data, :sha256]
  defstruct [:data, :sha256]
  @type t :: %__MODULE__{data: map(), sha256: String.t()}

  @doc "Exports the installed grammar with only explicit trusted consumer selections."
  @spec export(term(), term(), term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def export(bindings, contracts, limits, artifacts) do
    with {:ok, limits} <- AuthoringLimits.new(limits),
         {:ok, _} <- Envelope.admit(artifacts),
         true <- artifacts == Artifacts.current(),
         {:ok, reader} <- Limits.new(limits.data["reader"]),
         {:ok, bindings} <- bindings(bindings, reader),
         :ok <- Grammar.references(contracts, reader, "/contracts"),
         data =
           Map.merge(artifacts, %{
             "format" => "wotex.profile.authoring-contract@1",
             "bindings" => bindings,
             "contracts" => contracts,
             "limits" => limits.data
           }),
         {:ok, bytes} <- Envelope.encode(data) do
      {:ok,
       %__MODULE__{
         data: data,
         sha256: Grammar.hash("wotex.profile.authoring-contract@1\n" <> bytes)
       }}
    else
      false -> Error.refusal(:invalid_contract)
      error -> error
    end
  end

  @doc "Parses bounded contract bytes and verifies the installed artifacts and registrations."
  @spec parse(term()) :: {:ok, t()} | {:error, Error.t()}
  def parse(bytes) do
    with {:ok, data} <- Envelope.decode(bytes), do: document(data)
  end

  @doc "Revalidates an exact native Contract; a forged retained identity is refused."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{data: data, sha256: digest} = value) when map_size(value) == 3 do
    with {:ok, checked} <- document(data), true <- digest == checked.sha256 do
      {:ok, checked}
    else
      false -> Error.refusal(:invalid_contract)
      error -> error
    end
  end

  def new(_), do: Error.refusal(:invalid_contract)

  @doc "Returns the deterministic contract document bytes after native revalidation."
  @spec encode(term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(value) do
    with {:ok, value} <- new(value), do: Envelope.encode(value.data)
  end

  @doc "Returns the recomputed contract identity independently of its encoded document."
  @spec identity(term()) :: {:ok, String.t()} | {:error, Error.t()}
  def identity(value) do
    with {:ok, value} <- new(value), do: {:ok, value.sha256}
  end

  defp document(data) do
    with {:ok, _} <- Envelope.admit(data),
         :ok <- Grammar.fields(data, @fields, "/contract"),
         true <- data["format"] == "wotex.profile.authoring-contract@1" do
      export(
        data["bindings"],
        data["contracts"],
        data["limits"],
        Map.take(data, ~w(producer schemas semantic_rules))
      )
    else
      false -> Error.refusal(:invalid_contract)
      error -> error
    end
  end

  defp bindings(values, limits) do
    with {:ok, values} <- bounded(values, limits.data["max_bindings"], []),
         {:ok, _} <-
           Envelope.admit(
             Enum.map(values, fn value ->
               case value do
                 %Binding{data: data} -> data
                 other -> other
               end
             end)
           ) do
      checked =
        Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
          case Binding.to_map(value, limits) do
            {:ok, value} -> {:cont, {:ok, [value | acc]}}
            _ -> {:halt, Error.refusal(:invalid_contract, "/bindings")}
          end
        end)

      with {:ok, values} <- checked,
           values = Enum.sort_by(values, &{&1["id"], &1["version"]}),
           :ok <- Grammar.sorted_unique(values, &{&1["id"], &1["version"]}, "/bindings"),
           do: {:ok, values}
    end
  end

  defp bounded([], _, acc), do: {:ok, Enum.reverse(acc)}
  defp bounded([_ | _], 0, _), do: Error.refusal(:input_limit, "/bindings")
  defp bounded([value | rest], remaining, acc), do: bounded(rest, remaining - 1, [value | acc])
  defp bounded(_, _, _), do: Error.refusal(:invalid_contract, "/bindings")
end
