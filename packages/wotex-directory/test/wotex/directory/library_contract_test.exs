defmodule Wotex.Directory.LibraryContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "the OTP application has no callback module" do
    assert Application.load(:wotex_directory) in [
             :ok,
             {:error, {:already_loaded, :wotex_directory}}
           ]

    assert Application.spec(:wotex_directory, :mod) in [nil, [], :undefined]
  end

  test "loading the package does not register a process under its public namespaces" do
    assert Process.whereis(Wotex.Directory) == nil
    assert Process.whereis(Wotex.Directory.Service) == nil
    assert Process.whereis(Wotex.Directory.Repository) == nil
  end
end
