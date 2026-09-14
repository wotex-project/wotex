defmodule Wotex.Matter.CatalogueClient do
  @moduledoc false

  @behaviour Wotex.Matter.Client

  alias Wotex.Matter.{Descriptor, Error}

  @impl Wotex.Matter.Client
  def connect(options) do
    {:ok,
     %{
       owner: Keyword.fetch!(options, :owner),
       root_parts: Keyword.get(options, :root_parts, [1])
     }}
  end

  @impl Wotex.Matter.Client
  def request(handle, %{type: :read_paths, paths: paths} = message, timeout) do
    send(handle.owner, {:catalogue_request, message, timeout})
    {:ok, Enum.map(paths, &result(&1, handle.root_parts))}
  end

  def request(_, _, _), do: {:error, Error.new(:unexpected_request)}

  @impl Wotex.Matter.Client
  def disconnect(_), do: :ok

  defp result(path, root_parts) do
    value =
      case {path.endpoint, path.member} do
        {0, 0} -> [%{device_type: 0x0016, revision: 1}]
        {_, 0} -> [%{device_type: 0x0100, revision: 2}]
        {_, 1} -> [0x001D, 0x0006]
        {_, 2} -> []
        {0, 3} -> root_parts
        {_, 3} -> []
      end

    {:ok, element} = Descriptor.to_element(:attribute, path, :read, value)

    %{
      path: path,
      result: {:ok, %{path: path, value: element, data_version: path.endpoint}}
    }
  end
end
