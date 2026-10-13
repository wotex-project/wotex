defmodule Wotex.Profiles.Artifacts do
  @moduledoc "Installed compile-time authoring schemas, rule table and semantic release identity; no runtime I/O."

  @directory Path.expand("../../../priv/authoring", __DIR__)
  @files ~w(profile definition draft bundle semantic-rules)
  for name <- @files do
    @external_resource Path.join(@directory, name <> ".json")
  end

  @schemas Map.new(~w(profile definition draft bundle), fn name ->
             {name, Jason.decode!(File.read!(Path.join(@directory, name <> ".json")))}
           end)
  @rules Jason.decode!(File.read!(Path.join(@directory, "semantic-rules.json")))
  {:ok, bytes} =
    Wotex.JSON.encode(%{"schemas" => @schemas, "semantic_rules" => @rules},
      max_bytes: 2_097_152,
      max_depth: 32,
      max_nodes: 50_000,
      max_collection_size: 4096,
      max_string_bytes: 16_384
    )

  @identity Base.encode16(:crypto.hash(:sha256, "wotex.profile.authoring-release@1\n" <> bytes),
              case: :lower
            )
  @current %{
    "producer" => %{
      "id" => "urn:wotex:profiles:authoring",
      "version" => "1.0.0",
      "sha256" => @identity
    },
    "schemas" => @schemas,
    "semantic_rules" => @rules
  }

  @doc "Returns only installed literal data; consumers independently bind this assertion to their actual artifact."
  @spec current() :: %{String.t() => term()}
  def current, do: @current
end
