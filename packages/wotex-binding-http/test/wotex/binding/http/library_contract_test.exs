defmodule Wotex.Binding.HTTP.LibraryContractTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Binding.HTTP.{Client, Transport}

  test "loading the library starts no application callback" do
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

  test "each source and test file defines at most one module" do
    files = Path.wildcard("{lib,test}/**/*.{ex,exs}")

    for file <- files do
      source = File.read!(file)
      modules = Regex.scan(~r/^defmodule\s+/m, source)
      assert length(modules) <= 1, "#{file} defines multiple modules"
    end
  end

  test "application source has no callback or concrete network client" do
    sources = Path.wildcard("lib/**/*.ex") |> Enum.map_join("\n", &File.read!/1)
    refute sources =~ Enum.join(["use", "Application"], " ")
    refute sources =~ "def start("
    refute sources =~ Enum.join(["Application", "get_env"], ".")
  end
end
