defmodule Mix.Tasks.Wotex.Native.SourcesTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Native.Sources

  test "takes no options" do
    assert Sources.parse_args([]) == []
    assert_raise Mix.Error, fn -> Sources.parse_args(~w(--offline)) end
  end
end
