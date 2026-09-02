defmodule Wotex.Runtime.Credentials do
  @moduledoc """
  Port for resolving credential material immediately before a transport call.

  The first argument contains only selected TD security names and definitions.
  """

  alias Wotex.Form
  alias Wotex.Runtime.Context

  @type config :: term()

  @callback resolve(map(), Form.t(), Context.t(), config()) ::
              {:ok, term()} | {:error, term()}
end
