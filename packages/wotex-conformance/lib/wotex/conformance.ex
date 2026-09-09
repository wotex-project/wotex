defmodule Wotex.Conformance do
  @moduledoc """
  Subject-independent W3C Web of Things conformance evidence.

  Use `Wotex.Conformance.Corpus` to load verified vectors,
  `Wotex.Conformance.Target.External` to configure an isolated adapter, and
  `Wotex.Conformance.Runner` to produce a `Wotex.Conformance.Report`.

  `load_corpus/1` verifies a content-addressed corpus before any subject is
  invoked. `run/4` then evaluates that corpus against one immutable
  `Wotex.Conformance.Subject` through a consumer-supplied target adapter. The
  runner retains expected values on its side of the protocol and reduces target
  observations to digests before they become reportable results.

  Evidence is scoped to the exact subject artifact, corpus, claim, vector,
  protocol, and environment recorded by the report. A successful vector does
  not imply package-wide conformance, certification, interoperability, or
  stability. The library starts no application process and includes no tested
  subject as a production dependency.
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
