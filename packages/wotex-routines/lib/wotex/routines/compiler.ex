defmodule Wotex.Routines.Compiler do
  @moduledoc """
  Compiles complete routine sources and regenerates retained programs offline.

  `compile/4` takes a `Wotex.Routines.Source` or source map, an explicit context,
  `Wotex.Routines.Profile` and `Wotex.Routines.Limits`. It returns
  `{:ok, program}` with a `Wotex.Routines.Program`, or `{:error, error}` with a
  `Wotex.Routines.Error`. No binding, participant, child revision or parameter
  value is discovered at execution time.

  The context requires `"registry"`, `"bases"`, `"bindings"`, `"definitions"`,
  `"arguments"` and `"compiler_basis"`, including explicit empty collections
  where appropriate. Installed contracts and exact instance/resource mappings
  are supplied by the consumer. Child sources must form an acyclic, version-pinned
  closure. Expansion counts every possible path, including both conditional
  branches and each invocation copy, against the selected bounds.

  `current/4` recompiles the retained source with the supplied current context,
  profile and limits, then compares the entire regenerated program. It returns
  `:ok` or `{:error, error}`; recomputing hashes on altered IR cannot bypass this
  check. `to_map/3` performs the same regeneration using the retained context
  before returning `{:ok, data}`. That projection alone does not establish that
  the consumer's installed context is still current.

  Source, IR and compiler-basis digests identify distinct inputs. Their integrity
  does not authenticate installed code, qualify a device or admit execution.
  The consumer owns those checks and the custody of the supplied offline closure.
  """

  alias Wotex.Routines.{
    CompilationContext,
    Error,
    Expansion,
    Limits,
    Profile,
    Program,
    Source,
    Validation
  }

  @compiler_profile "wotex.routines.compiler@1"

  @doc "Resolves exact installed bindings and child sources, then expands every possible path."
  @spec compile(term(), term(), Profile.t(), Limits.t()) :: {:ok, Program.t()} | {:error, Error.t()}
  def compile(source, context, profile, limits) do
    with {:ok, profile} <- Profile.new(profile),
         {:ok, limits} <- Limits.new(limits),
         {:ok, source} <- Source.new(source, profile, limits),
         {:ok, context} <- CompilationContext.new(context, source, profile, limits),
         {:ok, ir} <- Expansion.build(source, context, profile, limits),
         {:ok, source_digest} <-
           Validation.hash(%{"source" => source.data, "context" => context.data}, limits),
         {:ok, ir_digest} <-
           Validation.hash(
             %{
               "source_digest" => source_digest,
               "ir" => ir,
               "profile" => profile.data,
               "compiler_profile" => @compiler_profile
             },
             limits
           ) do
      data = %{
        "format" => "wotex.routines.program@1",
        "source" => source.data,
        "context" => context.data,
        "profile" => profile.data,
        "json_limits" => limits.data,
        "compiler_profile" => @compiler_profile,
        "source_digest" => source_digest,
        "ir" => ir,
        "ir_digest" => ir_digest
      }

      with :ok <- Validation.bounded(data, limits), do: {:ok, %Program{data: data}}
    end
  end

  @doc "Regenerates complete retained inputs; caller-recomputed hashes cannot validate altered IR."
  @spec current(term(), term(), Profile.t(), Limits.t()) :: :ok | {:error, Error.t()}
  def current(program, context, profile, limits) do
    with {:ok, data, _} <- Validation.admit(program, limits, Program),
         :ok <-
           Validation.fields(
             data,
             ~w(format source context profile json_limits compiler_profile source_digest ir ir_digest)
           ),
         {:ok, rebuilt} <- compile(data["source"], context, profile, limits) do
      if rebuilt.data == data, do: :ok, else: Error.refusal(:stale_or_forged_program)
    end
  end

  @doc "Revalidates a program before returning its complete data representation."
  @spec to_map(term(), Profile.t(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(program, profile, limits) do
    with {:ok, data, _} <- Validation.admit(program, limits, Program),
         :ok <-
           Validation.fields(
             data,
             ~w(format source context profile json_limits compiler_profile source_digest ir ir_digest)
           ),
         :ok <- current(program, data["context"], profile, limits) do
      {:ok, data}
    end
  end
end
