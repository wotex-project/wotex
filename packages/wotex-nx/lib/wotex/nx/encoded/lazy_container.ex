defimpl Nx.LazyContainer, for: Wotex.Nx.Encoded do
  @moduledoc """
  Delegates lazy numerical traversal of an encoded window to its stored Nx batch.

  This protocol implementation lets `Wotex.Nx.Encoded` participate in
  `Nx.LazyContainer` consumers such as numerical compilation. `traverse/3`
  forwards the caller's accumulator and callback to the contained `Nx.Batch`,
  preserving its tensor templates, deferred stack computation and traversal
  order.

  Observation admission, feature ordering, tensor creation and provenance
  assembly occur in `Wotex.Nx.Encoder`. Traversal neither repeats those checks
  nor selects a backend, runs a model or interprets an output as an Action.
  Consumers construct encoded windows through the encoder before passing them
  to numerical execution.
  """

  @spec traverse(Wotex.Nx.Encoded.t(), acc, (Nx.Tensor.t(), (-> Nx.Tensor.t()), acc ->
                                               {term(), acc})) ::
          {term(), acc}
        when acc: term()
  def traverse(%Wotex.Nx.Encoded{batch: batch}, acc, fun) do
    Nx.LazyContainer.traverse(batch, acc, fun)
  end
end
