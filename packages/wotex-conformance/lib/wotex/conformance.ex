defmodule Wotex.Conformance do
  @moduledoc """
  Subject-independent W3C Web of Things conformance evidence.

  Use `Wotex.Conformance.Corpus` to load verified vectors,
  `Wotex.Conformance.Target.External` to configure an isolated adapter, and
  `Wotex.Conformance.Runner` to produce a `Wotex.Conformance.Report`.
  """

  alias Wotex.Conformance.{Corpus, Report, Runner, Subject}

  @doc "Loads a content-addressed vector corpus."
  @spec load_corpus(Path.t()) :: {:ok, Corpus.t()} | {:error, Wotex.Conformance.Error.t()}
  defdelegate load_corpus(path), to: Corpus, as: :load

  @doc "Runs a verified corpus against an immutable subject artifact."
  @spec run(Corpus.t(), Subject.t(), term(), keyword()) ::
          {:ok, Report.t()} | {:error, Wotex.Conformance.Error.t()}
  defdelegate run(corpus, subject, target, options), to: Runner
end
