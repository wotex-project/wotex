defmodule Wotex.Profiles.CLI do
  @moduledoc false

  alias Wotex.Profiles.{Contract, Draft, Envelope, Error, Finalized, Validation, ValidationReport}

  @doc false
  @spec execute(:validate | :finalize, [String.t()]) :: {0 | 1 | 2, binary()}
  def execute(kind, arguments) do
    with {:ok, options} <- arguments(kind, arguments, %{}),
         {:ok, bytes} <- read(options["--contract"], 2_097_152),
         {:ok, contract} <- Contract.parse(bytes),
         {:ok, candidate} <-
           read(options["--candidate"], contract.data["limits"]["max_bundle_bytes"]),
         {:ok, capture} <- capture(options, contract) do
      action(kind, candidate, contract, capture, options)
    else
      {:error, %Error{} = error} -> failure(error)
    end
  end

  defp arguments(kind, [], options) do
    required =
      if kind == :validate,
        do: ~w(--contract --candidate),
        else: ~w(--contract --candidate --output)

    if Enum.all?(required, &Map.has_key?(options, &1)),
      do: {:ok, options},
      else: Error.refusal(:invalid_input)
  end

  defp arguments(kind, [key, value | rest], options) do
    allowed =
      if kind == :validate,
        do: ~w(--contract --candidate --capture),
        else: ~w(--contract --candidate --output)

    valid_value = is_binary(value) and value != "" and not String.starts_with?(value, "--")

    if key in allowed and valid_value and
         not Map.has_key?(options, key),
       do: arguments(kind, rest, Map.put(options, key, value)),
       else: Error.refusal(:invalid_input)
  end

  defp arguments(_, _, _), do: Error.refusal(:invalid_input)

  defp read(path, maximum) do
    case File.open(path, [:read, :binary]) do
      {:ok, file} ->
        result =
          try do
            case IO.binread(file, maximum + 1) do
              :eof -> {:ok, ""}
              bytes when is_binary(bytes) and byte_size(bytes) <= maximum -> {:ok, bytes}
              bytes when is_binary(bytes) -> Error.refusal(:input_limit)
              _ -> Error.refusal(:invalid_input)
            end
          after
            File.close(file)
          end

        result

      _ ->
        Error.refusal(:invalid_input)
    end
  end

  defp capture(options, contract) do
    if Map.has_key?(options, "--capture") do
      with {:ok, bytes} <-
             read(options["--capture"], contract.data["limits"]["reader"]["max_bytes"]),
           {:ok, capture, _} <-
             Wotex.Profiles.Parser.decode(bytes, contract.data["limits"]["reader"]),
           do: {:ok, capture}
    else
      {:ok, nil}
    end
  end

  defp action(:validate, bytes, contract, capture, _) do
    case Validation.check(bytes, contract, capture) do
      {:ok, report} -> report(report, contract)
      {:error, error} -> failure(error)
    end
  end

  defp action(:finalize, bytes, contract, _, options) do
    case Draft.finalize(bytes, contract) do
      {:ok, %Finalized{} = value} ->
        case File.write(options["--output"], value.bundle_bytes) do
          :ok ->
            {:ok, encoded} =
              Envelope.encode(%{
                "format" => "wotex.profile.finalized@1",
                "draft_sha256" => value.draft_sha256,
                "bundle_sha256" => value.bundle_sha256,
                "contract_sha256" => value.contract_sha256
              })

            {0, encoded}

          _ ->
            failure(%Error{code: :invalid_input, path: ""})
        end

      {:ok, report} ->
        report(report, contract)

      {:error, error} ->
        failure(error)
    end
  end

  defp report(report, contract) do
    case ValidationReport.encode(report, contract) do
      {:ok, bytes} -> {if(report.data["disposition"] == "compatible", do: 0, else: 1), bytes}
      {:error, error} -> failure(error)
    end
  end

  defp failure(error) do
    {:ok, bytes} = Envelope.encode(%{"error" => %{"code" => Atom.to_string(error.code)}})
    {2, bytes}
  end
end
