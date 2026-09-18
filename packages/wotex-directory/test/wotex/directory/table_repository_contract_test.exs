defmodule Wotex.Directory.TableRepositoryContractTest do
  @moduledoc false

  use ExUnit.Case, async: true
  # Credo's PassAsyncInTestCases check crashes on a multi-module `use` without options.
  use Wotex.Directory.{RepositoryContract, PublicOperationContract, ReferenceConsumerContract},
      []

  alias Wotex.Directory.{TableRepository, TestIdentifier}

  setup do
    table = TableRepository.new([:scope_a, :scope_b])
    identifiers = List.duplicate("urn:example:anonymous", 4)

    identifier =
      start_supervised!(%{id: :identifier, start: {TestIdentifier, :start_link, [identifiers]}})

    fixture = %{
      repository: {TableRepository, table},
      scope: :scope_a,
      other_scope: :scope_b,
      identifier: identifier,
      generation: fn "table:" <> generation -> String.to_integer(generation) end
    }

    %{repository_fixture: fixture}
  end
end
