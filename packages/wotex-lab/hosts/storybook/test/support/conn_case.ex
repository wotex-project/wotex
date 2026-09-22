defmodule WotexLabStorybookWeb.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint WotexLabStorybookWeb.Endpoint

      import Phoenix.{ConnTest, LiveViewTest}
      import Plug.Conn
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
