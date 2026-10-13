defmodule Wotex.Routines.ValueContract do
  @moduledoc false

  alias Wotex.Routines.{Error, Limits, Unit, Validation}

  @spec validate(term(), Limits.t()) :: :ok | {:error, Error.t()}
  def validate(data, limits) do
    with :ok <- Validation.fields(data, ~w(type unit enum), [], "/value"),
         :ok <- Validation.choice(data["type"], ~w(boolean integer enum), "/value/type") do
      case data do
        %{"type" => "boolean", "unit" => nil, "enum" => []} ->
          :ok

        %{"type" => "integer", "enum" => [], "unit" => unit} ->
          case Unit.new(unit, limits) do
            {:ok, _} -> :ok
            error -> error
          end

        %{"type" => "enum", "unit" => nil, "enum" => values} ->
          Validation.strings(values, "/value/enum", true)

        _ ->
          Error.refusal(:invalid_value_contract, "/value")
      end
    end
  end

  @spec accepts(term(), term(), Limits.t()) :: :ok | {:error, Error.t()}
  def accepts(contract, value, limits) do
    with {:ok, contract, _} <- Validation.admit(contract, limits, nil),
         :ok <- validate(contract, limits) do
      check_value(contract, value, limits)
    end
  end

  defp check_value(%{"type" => "boolean"}, value, _) when is_boolean(value), do: :ok

  defp check_value(%{"type" => "integer", "unit" => unit}, value, limits) do
    case Unit.convert(value, unit, unit, limits) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp check_value(%{"type" => "enum", "enum" => values}, value, _) do
    Validation.choice(value, values, "/value")
  end

  defp check_value(_, _, _), do: Error.refusal(:invalid_value, "/value")
end
