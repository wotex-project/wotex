defimpl Nx.LazyContainer, for: Wotex.Nx.Encoded do
  @moduledoc false

  @spec traverse(Wotex.Nx.Encoded.t(), acc, (Nx.Tensor.t(), (-> Nx.Tensor.t()), acc ->
                                               {term(), acc})) ::
          {term(), acc}
        when acc: term()
  def traverse(%Wotex.Nx.Encoded{batch: batch}, acc, fun) do
    Nx.LazyContainer.traverse(batch, acc, fun)
  end
end
