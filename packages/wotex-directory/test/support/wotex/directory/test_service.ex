defmodule Wotex.Directory.TestService do
  @moduledoc false

  alias Wotex.Directory.{Context, Fixtures, MemoryRepository, Service, TestAuthorization}
  alias Wotex.Directory.{TestClock, TestIdentifier}

  @default_now ~U[2026-09-02 10:00:00Z]

  @spec build(keyword()) :: map()
  def build(options \\ []) do
    {:ok, repository} =
      MemoryRepository.start_link(
        entries: Keyword.get(options, :entries, []),
        revision: Keyword.get(options, :revision, 0)
      )

    identifiers =
      Keyword.get(options, :identifiers, ["urn:uuid:00000000-0000-4000-8000-000000000001"])

    {:ok, identifier} = TestIdentifier.start_link(identifiers)

    authorization =
      Keyword.get(options, :authorization, %{test_pid: self(), result: :ok})

    now = Keyword.get(options, :now, @default_now)

    service_options = [
      repository: {MemoryRepository, repository},
      authorization: {TestAuthorization, authorization},
      clock: {TestClock, now},
      identifier: {TestIdentifier, identifier},
      introduction: Fixtures.thing_description("urn:example:directory"),
      default_page_limit: Keyword.get(options, :default_page_limit, 2),
      maximum_page_limit: Keyword.get(options, :maximum_page_limit, 4),
      default_expiry_batch_limit: Keyword.get(options, :default_expiry_batch_limit, 2),
      maximum_expiry_batch_limit: Keyword.get(options, :maximum_expiry_batch_limit, 4),
      expiry_strategy: Keyword.get(options, :expiry_strategy, :purge),
      maximum_patch_depth: Keyword.get(options, :maximum_patch_depth, 8),
      maximum_patch_nodes: Keyword.get(options, :maximum_patch_nodes, 100)
    ]

    {:ok, service} = Service.new(service_options)

    context =
      Context.new!(:principal,
        authorization: :authorization_context,
        repository: :repository_context
      )

    %{
      service: service,
      context: context,
      repository: repository,
      identifier: identifier,
      now: now
    }
  end
end
