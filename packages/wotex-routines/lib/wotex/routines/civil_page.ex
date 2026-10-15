defmodule Wotex.Routines.CivilPage do
  @moduledoc """
  The complete native result of one finite civil query.

  Returned by `Wotex.Routines.Civil.page/3`, it retains a native
  `Wotex.Routines.CivilRequest`, checked `Wotex.Routines.Time` projection and
  ordered occurrence maps in `:request`, `:time` and `:occurrences`. Completeness
  covers only that request's local-date span and UTC window. An empty list says nothing about
  later dates; no global ordinal, continuation or exhaustion flag is present.

  Use `Wotex.Routines.Civil.to_map/2` to regenerate the complete retained inputs
  and require exact equality before returning the occurrences-only JSON map.
  Use `Wotex.Routines.Civil.event/6` to bind an exact regenerated member to the
  current clock generation and matching compiled due trigger. A constructed
  struct or edited occurrence map is not trusted without those checks.

  The wire projection omits the native request/database and retained time map;
  retain or rebuild immutable inputs and recompute for later use. Original
  identities survive query overlap and clock reprojection, but authenticate no
  producer/database custody. Pages and event descriptors are inert; the consumer
  owns admission, current time/window guards, persistent no-repeat history and
  execution authority.
  """

  alias Wotex.Routines.CivilRequest

  @enforce_keys [:request, :time, :occurrences]
  defstruct [:request, :time, :occurrences]

  @type t :: %__MODULE__{request: CivilRequest.t(), time: map(), occurrences: [map()]}
end
