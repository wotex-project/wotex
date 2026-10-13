defmodule Wotex.Routines.Codec do
  @moduledoc "Bounded source JSON admission using core's public offline parser and canonical encoding."

  alias Wotex.Routines.{Error, Limits, Profile, Source, Validation}

  @doc "Decodes and structurally validates closed source under both explicit limit sets."
  @spec decode_source(term(), Profile.t(), Limits.t()) :: {:ok, Source.t()} | {:error, Error.t()}
  def decode_source(bytes, profile, limits) do
    with {:ok, profile} <- Profile.new(profile),
         {:ok, limits} <- Limits.new(limits),
         true <- is_binary(bytes) and byte_size(bytes) <= profile.data["source_bytes"],
         selected = %{
           limits.data
           | "max_bytes" => min(limits.data["max_bytes"], profile.data["source_bytes"]),
             "max_depth" => min(limits.data["max_depth"], profile.data["source_depth"])
         },
         {:ok, data} <- Wotex.JSON.decode(bytes, Validation.json_options(selected)) do
      Source.new(data, profile, limits)
    else
      {:error, %Error{}} = error -> error
      _ -> Error.refusal(:source_decode_error)
    end
  end

  @doc "Revalidates source before producing deterministic complete canonical JSON bytes."
  @spec encode_source(term(), Profile.t(), Limits.t()) :: {:ok, binary()} | {:error, Error.t()}
  def encode_source(source, profile, limits) do
    with {:ok, source} <- Source.new(source, profile, limits),
         {:ok, limits} <- Limits.new(limits) do
      case Wotex.JSON.encode(source.data, Validation.json_options(limits.data)) do
        {:ok, bytes} -> {:ok, bytes}
        _ -> Error.refusal(:source_encode_error)
      end
    end
  end
end
