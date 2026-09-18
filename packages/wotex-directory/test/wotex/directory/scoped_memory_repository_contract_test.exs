defmodule Wotex.Directory.ScopedMemoryRepositoryContractTest do
  @moduledoc false

  use ExUnit.Case, async: true
  # Credo's PassAsyncInTestCases check crashes on a multi-module `use` without options.
  use Wotex.Directory.{RepositoryContract, PublicOperationContract, ReferenceConsumerContract},
      []

  alias Wotex.Directory.{MemoryRepository, ScopedMemoryRepository, TestIdentifier}

  setup do
    scopes = [:scope_a, :scope_b]

    repositories =
      Map.new(scopes, fn scope ->
        {scope, start_supervised!(%{id: scope, start: {MemoryRepository, :start_link, [[]]}})}
      end)

    identifiers = List.duplicate("urn:example:anonymous", 4)

    identifier =
      start_supervised!(%{id: :identifier, start: {TestIdentifier, :start_link, [identifiers]}})

    fixture = %{
      repository: {ScopedMemoryRepository, repositories},
      scope: :scope_a,
      other_scope: :scope_b,
      identifier: identifier,
      generation: fn "generation:" <> generation -> String.to_integer(generation) end
    }

    %{repository_fixture: fixture}
  end
end
