defmodule Wotex.Matter.ProcessCommandTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter.Native.ProcessCommand

  test "child commands receive no inherited environment" do
    executable = System.find_executable("env")
    assert is_binary(executable)
    assert {"", 0} = ProcessCommand.run(executable, [])
  end
end
