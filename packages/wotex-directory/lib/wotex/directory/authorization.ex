defmodule Wotex.Directory.Authorization do
  @moduledoc """
  Consumer authorization port.

  Implementations decide policy and return `:ok`, `:deny`, or an adapter
  failure. The directory invokes this port before repository access.
  """

  @type operation :: :register | :get | :replace | :patch | :delete | :list | :expire
  @type target :: :collection | {:entry, String.t()}

  @doc "Authorizes one directory operation before any repository access occurs."
  @callback authorize(
              state :: term(),
              principal :: term(),
              operation(),
              target(),
              context :: term()
            ) :: :ok | :deny | {:error, term()}
end
