defmodule WotexLabStorybook.Stories.Root do
  use PhoenixStorybook.Index

  @spec folder_name() :: String.t()
  def folder_name, do: "Wotex qualification"

  @spec entry(String.t()) :: keyword()
  def entry("islands") do
    [name: "Live island integration"]
  end
end
