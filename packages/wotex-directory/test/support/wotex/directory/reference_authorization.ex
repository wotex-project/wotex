defmodule Wotex.Directory.ReferenceAuthorization do
  @moduledoc false

  @behaviour Wotex.Directory.Authorization

  @impl Wotex.Directory.Authorization
  def authorize(%{observer: observer, policy: policy}, principal, operation, target, context) do
    arguments = [principal, operation, target, context]
    send(observer, {:reference_port, :authorize, self(), arguments})
    policy.(arguments)
  end
end
