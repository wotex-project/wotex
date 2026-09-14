defmodule Wotex.Binding.HTTP.LibraryContractTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Binding.HTTP.{Client, Transport}

  test "WBH-L11-N loading the library defines no application callback" do
    assert Application.spec(:wotex_binding_http, :mod) in [nil, [], :undefined]
  end

  test "client and Runtime transport callback surfaces remain exact" do
    assert Client.behaviour_info(:callbacks) |> Enum.sort() ==
             [close: 2, request: 3, subscribe: 4]

    assert function_exported?(Transport, :request, 3)
    assert function_exported?(Transport, :subscribe, 4)
    assert function_exported?(Transport, :unsubscribe, 4)
    assert function_exported?(Transport, :decode_frame, 3)
  end
end
