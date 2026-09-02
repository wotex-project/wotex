defmodule WotexContinuum.LibraryContractTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias WotexContinuum.{Error, Schema}

  test "loading the library starts no application callback" do
    assert Application.load(:wotex_continuum) in [
             :ok,
             {:error, {:already_loaded, :wotex_continuum}}
           ]

    assert Application.spec(:wotex_continuum, :mod) == []
  end

  test "source has no process, ambient configuration, framework, or persistence boundary" do
    source =
      Path.expand("../../lib/**/*.ex", __DIR__)
      |> Path.wildcard()
      |> Enum.map_join("\n", &File.read!/1)

    forbidden = [
      "use GenServer",
      "use Supervisor",
      "Application.get_env",
      "Application.fetch_env",
      "System.get_env",
      "Ecto.Repo",
      "use Phoenix",
      "use Oban",
      ":ets."
    ]

    for token <- forbidden do
      refute source =~ token
    end
  end

  test "all normative schemas are valid JSON objects" do
    paths = Path.wildcard(Path.expand("../../priv/schemas/*.json", __DIR__))
    assert length(paths) == 3

    for path <- paths do
      assert {:ok, %{"$schema" => _, "$id" => _, "$defs" => _}} =
               path |> File.read!() |> Jason.decode()
    end

    assert Schema.ids() == ["WCT.01", "WCT.02", "WCT.03"]

    for id <- Schema.ids() do
      assert {:ok, source} = Schema.fetch(id)
      assert {:ok, %{"$schema" => _}} = Jason.decode(source)

      assert {:ok, %{id: ^id, schema_version: "1.0.0", digest: "sha256:" <> digest}} =
               Schema.info(id)

      assert byte_size(digest) == 64
    end

    assert {:error, %Error{code: :unknown_schema}} = Schema.fetch("WCT.99")
    assert {:error, %Error{code: :invalid_type}} = Schema.fetch(:unknown)
  end

  test "registered kinds are stable and unique" do
    kinds = WotexContinuum.kinds()
    assert length(kinds) == 13
    assert kinds == Enum.uniq(kinds)
    assert kinds == Enum.sort(kinds)
  end
end
