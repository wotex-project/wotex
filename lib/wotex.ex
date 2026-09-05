defmodule Wotex do
  @moduledoc """
  Consumer-neutral W3C Web of Things values, Thing Description mechanics, and
  reusable Thing Models.

  The production standards baseline is W3C WoT Thing Description 1.1,
  Recommendation 5 December 2023. Use `Wotex.ThingDescription` for operational
  Thing metadata and `Wotex.ThingModel` for reusable model templates.

  Wotex gives Elixir code one storage-neutral representation for Thing
  Descriptions, Interaction Affordances, Forms, DataSchemas, and security
  schemes. It validates declarations and preserves extension members, but does
  not execute protocols or own persistence, identity, authorization,
  credentials, supervision, or canonical Thing state.

  ## Start with a Thing Description

      json = ~S({
        "@context":"https://www.w3.org/2022/wot/td/v1.1",
        "title":"Lamp",
        "security":["nosec_sc"],
        "securityDefinitions":{"nosec_sc":{"scheme":"nosec"}}
      })

      {:ok, td} = Wotex.ThingDescription.parse(json)
      Wotex.ThingDescription.to_map(td)["title"]
      #=> "Lamp"

  Loading the package starts no process and performs no network or runtime
  filesystem access. The bundled TD schema is compiled into the package.
  """

  @td_context_1_1 "https://www.w3.org/2022/wot/td/v1.1"
  @td_media_type "application/td+json"
  @tm_media_type "application/tm+json"

  @doc """
  Returns the exact TD 1.1 context URI supported as the production baseline.

      Wotex.td_context_1_1()
      #=> "https://www.w3.org/2022/wot/td/v1.1"
  """
  @spec td_context_1_1() :: String.t()
  def td_context_1_1, do: @td_context_1_1

  @doc """
  Returns the registered media type for a JSON Thing Description.

      Wotex.td_media_type()
      #=> "application/td+json"
  """
  @spec td_media_type() :: String.t()
  def td_media_type, do: @td_media_type

  @doc """
  Returns the registered media type for a JSON Thing Model.

      Wotex.tm_media_type()
      #=> "application/tm+json"
  """
  @spec tm_media_type() :: String.t()
  def tm_media_type, do: @tm_media_type
end
