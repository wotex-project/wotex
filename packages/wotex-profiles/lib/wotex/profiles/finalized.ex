defmodule Wotex.Profiles.Finalized do
  @moduledoc "Derived canonical bundle bytes and separate original-draft, bundle and contract identities."

  @enforce_keys [:bundle_bytes, :draft_sha256, :bundle_sha256, :contract_sha256]
  defstruct [:bundle_bytes, :draft_sha256, :bundle_sha256, :contract_sha256]

  @type t :: %__MODULE__{
          bundle_bytes: binary(),
          draft_sha256: String.t(),
          bundle_sha256: String.t(),
          contract_sha256: String.t()
        }
end
