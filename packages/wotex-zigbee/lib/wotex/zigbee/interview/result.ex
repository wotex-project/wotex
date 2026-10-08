defmodule Wotex.Zigbee.Interview.Result do
  @moduledoc """
  Bounded observations from one owner-epoch interview.

  `outcome` is `:complete` only when the requested inspection finishes without
  an issue. A `:partial` result retains completed and unfinished steps, NCP
  admission, later ZDO/ZCL responses and APS confirmation separately. Issues
  describe unavailable, rejected, conflicting or malformed evidence; they
  contain no external exception messages or credentials.

  `identity_matches` means that the successful IEEE callback matched the
  expected raw identity and route. ZDO callbacks lack an independent host
  transaction token and provide no cryptographic authentication or replay
  proof. Descriptor duplicates remain in their original lists; duplicate or
  unrelated indications remain in the owner's ordinary bounded event queue.
  Basic records preserve order, duplicate IDs, statuses, types and raw bytes.
  The NCP's reported security flag is retained without upgrading its trust.
  """

  alias Wotex.Zigbee.{Event, Reply, ZCL}

  @enforce_keys [:peer_ieee, :route_address, :owner_epoch, :outcome, :identity_matches, :steps]
  defstruct [:peer_ieee, :route_address, :owner_epoch, :outcome, :identity_matches, :steps]

  @type stage :: :identity | :node | :active | {:simple, byte()} | {:basic, byte()}
  @type step :: %{
          stage: stage(),
          admission: Reply.t() | nil,
          response: Event.t() | nil,
          confirmation: Event.t() | nil,
          attributes: ZCL.decoded() | nil,
          issues: [atom()]
        }
  @type t :: %__MODULE__{
          peer_ieee: <<_::64>>,
          route_address: 0..0xFFF7,
          owner_epoch: reference(),
          outcome: :complete | :partial,
          identity_matches: boolean(),
          steps: [step()]
        }
end
