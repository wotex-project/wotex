defmodule Wotex.Routines.CalendarPage do
  @moduledoc "Retained native calendar calculation. Regenerate through Calendar before projecting or binding an event."

  alias Wotex.Routines.{CalendarCursor, CalendarRequest}
  @enforce_keys [:request, :time, :occurrences, :next_cursor]
  defstruct [:request, :time, :occurrences, :next_cursor]

  @type t :: %__MODULE__{
          request: CalendarRequest.t(),
          time: map(),
          occurrences: [map()],
          next_cursor: CalendarCursor.t() | nil
        }
end
