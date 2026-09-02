defmodule Wotex.Directory.Authorization do
  @moduledoc """
  Consumer authorization port.

  Implementations decide policy and return `:ok`, `:deny`, or an adapter
  failure. The directory invokes this port before repository access.
  """

  @type operation :: :register | :get | :replace | :patch | :delete | :list | :expire
  @type target :: :collection | {:entry, String.t()}

  @callback authorize(
              state :: term(),
              principal :: term(),
              operation(),
              target(),
              context :: term()
            ) :: :ok | :deny | {:error, term()}
end
