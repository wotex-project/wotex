defmodule Wotex.Directory do
  @moduledoc """
  Storage-neutral W3C Web of Things Thing Description Directory mechanics.

  A `Wotex.Directory.Service` carries explicit consumer ports. Operations are
  synchronous, start no process, and return deterministic tagged results.

  The facade implements registration, retrieval, replacement, merge-patch,
  deletion, bounded listing, and expiry. It validates Thing Descriptions
  through `Wotex.ThingDescription`, evaluates authorization before repository
  access, and treats repository implementations as consumer-owned
  infrastructure. No operation contacts or controls the described Thing.

  Registration metadata follows the W3C Web of Things Discovery model. The
  directory assigns server-controlled timestamps, keeps response-only
  retrieval data out of storage, and uses entry versions for conditional
  mutation. Errors are returned as `Wotex.Directory.Error` values so callers
  can distinguish validation, policy, repository, and conflict failures.

  Build a `Wotex.Directory.Service` with the required ports, create a
  `Wotex.Directory.Context` for each request, and call this module at the
  application boundary. Transport adapters remain responsible for mapping
  HTTP or other protocol concepts onto these transport-independent results.
  """

  alias Wotex.Directory.{
    Context,
    Cursor,
    Entry,
    Error,
    Expiry,
    Identifier,
    MergePatch,
    Mutation,
    Page,
    Query,
    Registration,
    Service,
    ThingDescriptions
  }

  @type result(value) :: {:ok, value} | {:error, Error.t()}

  @doc """
  Registers a named or anonymous Thing Description.

  Named registration has Discovery PUT semantics: a missing identifier is
  created and an existing identifier is replaced. Anonymous registration uses
  the configured identifier port and reports collisions explicitly.
  """
  @spec register(Service.t(), Wotex.ThingDescription.t(), Context.t(), keyword()) ::
          result(Mutation.t())
  def register(service, thing_description, context, options \\ [])

  def register(%Service{} = service, thing_description, %Context{} = context, options) do
    with :ok <- valid_context(context, :register),
         :ok <- valid_options(options, [:registration], :register),
         :ok <- authorize(service, context, :register, :collection),
         {:ok, base, extracted_registration} <-
           ThingDescriptions.normalize_and_extract(
             thing_description,
             service.thing_description_options,
             :register
           ),
         {:ok, registration_input} <-
           registration_input(extracted_registration, options, :register),
         {:ok, now} <- now(service, :register),
         {:ok, identified, identifier, kind} <- ensure_identifier(service, base, :register) do
      with :ok <- authorize_registration_target(service, context, identifier, kind) do
        register_identified(
          service,
          identified,
          identifier,
          kind,
          registration_input,
          now,
          context
        )
      end
    end
  end

  def register(_, _, _, _),
    do: {:error, Error.new(:invalid_request, :validation, :register)}

  @doc """
  Retrieves an active entry and assigns `registration.retrieved` on the returned
  value without changing persisted registration information.
  """
  @spec get(Service.t(), String.t(), Context.t()) :: result(Entry.t())
  def get(%Service{} = service, identifier, %Context{} = context) do
    with :ok <- valid_context(context, :get),
         :ok <- valid_identifier(identifier, :get),
         :ok <- authorize(service, context, :get, {:entry, identifier}),
         {:ok, entry} <- fetch(service, identifier, context, :get),
         {:ok, now} <- now(service, :get),
         :ok <- active(entry, now, :get) do
      {:ok, Entry.mark_retrieved(entry, now)}
    end
  end

  def get(_, identifier, _),
    do:
      {:error,
       Error.new(:invalid_request, :validation, :get, identifier: safe_identifier(identifier))}

  @doc """
  Replaces an existing active entry with a complete Thing Description.
  """
  @spec replace(
          Service.t(),
          String.t(),
          Wotex.ThingDescription.t(),
          Context.t(),
          keyword()
        ) :: result(Mutation.t())
  def replace(service, identifier, thing_description, context, options \\ [])

  def replace(
        %Service{} = service,
        identifier,
        thing_description,
        %Context{} = context,
        options
      ) do
    with :ok <- valid_context(context, :replace),
         :ok <- valid_identifier(identifier, :replace),
         :ok <- valid_options(options, [:if_version, :registration], :replace),
         :ok <- authorize(service, context, :replace, {:entry, identifier}),
         {:ok, existing} <- fetch(service, identifier, context, :replace),
         {:ok, now} <- now(service, :replace),
         :ok <- active(existing, now, :replace),
         {:ok, expected_version} <- expected_version(existing, options, :replace),
         {:ok, base, extracted_registration} <-
           ThingDescriptions.normalize_and_extract(
             thing_description,
             service.thing_description_options,
             :replace
           ),
         :ok <- matching_identifier(identifier, ThingDescriptions.id(base), :replace),
         {:ok, registration_input} <-
           registration_input(extracted_registration, options, :replace),
         {:ok, registration} <-
           Registration.refresh(existing.registration, now, registration_input, :replace),
         {:ok, replacement} <-
           Entry.new(identifier, base, registration,
             version: existing.version + 1,
             state: :active
           ),
         {:ok, stored} <-
           replace_entry(service, replacement, expected_version, context, :replace) do
      {:ok, %Mutation{operation: :replace, status: :replaced, entry: stored}}
    end
  end

  def replace(_, identifier, _, _, _),
    do:
      {:error,
       Error.new(:invalid_request, :validation, :replace, identifier: safe_identifier(identifier))}

  @doc """
  Applies a bounded RFC 7396 JSON Merge Patch and validates the resulting Thing
  Description before one conditional repository replacement.
  """
  @spec patch(Service.t(), String.t(), map(), Context.t(), keyword()) ::
          result(Mutation.t())
  def patch(service, identifier, merge_patch, context, options \\ [])

  def patch(%Service{} = service, identifier, merge_patch, %Context{} = context, options) do
    with :ok <- valid_context(context, :patch),
         :ok <- valid_identifier(identifier, :patch),
         :ok <- valid_options(options, [:if_version], :patch),
         :ok <- valid_patch(merge_patch),
         :ok <- authorize(service, context, :patch, {:entry, identifier}),
         {:ok, existing} <- fetch(service, identifier, context, :patch),
         {:ok, now} <- now(service, :patch),
         :ok <- active(existing, now, :patch),
         {:ok, expected_version} <- expected_version(existing, options, :patch),
         {:ok, merged} <- merge_patch(service, existing, merge_patch),
         {:ok, base, registration_map} <-
           ThingDescriptions.from_enriched_map(
             merged,
             service.thing_description_options,
             :patch
           ),
         :ok <- matching_identifier(identifier, ThingDescriptions.id(base), :patch),
         {:ok, registration} <-
           Registration.from_patch(existing.registration, now, registration_map, :patch),
         {:ok, replacement} <-
           Entry.new(identifier, base, registration,
             version: existing.version + 1,
             state: :active
           ),
         {:ok, stored} <-
           replace_entry(service, replacement, expected_version, context, :patch) do
      {:ok, %Mutation{operation: :patch, status: :patched, entry: stored}}
    end
  end

  def patch(_, identifier, _, _, _),
    do:
      {:error,
       Error.new(:invalid_request, :validation, :patch, identifier: safe_identifier(identifier))}

  @doc """
  Conditionally deletes one directory entry. No lifecycle operation is applied
  to a Thing outside the directory.
  """
  @spec delete(Service.t(), String.t(), Context.t(), keyword()) :: result(Mutation.t())
  def delete(service, identifier, context, options \\ [])

  def delete(%Service{} = service, identifier, %Context{} = context, options) do
    with :ok <- valid_context(context, :delete),
         :ok <- valid_identifier(identifier, :delete),
         :ok <- valid_options(options, [:if_version], :delete),
         :ok <- authorize(service, context, :delete, {:entry, identifier}),
         {:ok, existing} <- fetch(service, identifier, context, :delete),
         {:ok, expected_version} <- expected_version(existing, options, :delete),
         :ok <- delete_entry(service, identifier, expected_version, context) do
      {:ok, %Mutation{operation: :delete, status: :deleted, entry: existing}}
    end
  end

  def delete(_, identifier, _, _),
    do:
      {:error,
       Error.new(:invalid_request, :validation, :delete, identifier: safe_identifier(identifier))}

  @doc """
  Builds and executes the supported bounded listing query.

  Options are `:limit`, `:format`, `:cursor`, and `:profile`. The `:cursor`
  value is the opaque `next_cursor` of a preceding page.
  """
  @spec list(Service.t(), Context.t(), keyword()) :: result(Page.t())
  def list(service, context, options \\ [])

  def list(%Service{} = service, %Context{} = context, options) do
    bounds = [
      default_limit: service.default_page_limit,
      max_limit: service.max_page_limit
    ]

    with {:ok, query} <- Query.new(options, bounds) do
      query(service, query, context)
    end
  end

  def list(_, _, _),
    do: {:error, Error.new(:invalid_request, :validation, :list)}

  @doc """
  Executes an existing listing query. Other profiles fail explicitly.
  """
  @spec query(Service.t(), Query.t(), Context.t()) :: result(Page.t())
  def query(%Service{} = service, %Query{} = query, %Context{} = context) do
    with :ok <- valid_context(context, :list),
         :ok <- Query.validate(query, service.max_page_limit),
         {:ok, cursor} <- listing_cursor(query),
         :ok <- authorize(service, context, :list, :collection),
         {:ok, active_at} <- now(service, :list),
         {:ok, page} <- list_entries(service, query, cursor, active_at, context),
         :ok <- Page.validate(page, query, active_at) do
      {:ok, Page.mark_retrieved(page, active_at)}
    end
  end

  def query(_, _, _),
    do: {:error, Error.new(:invalid_request, :validation, :list)}

  @doc """
  Executes one authorized, caller-scheduled, bounded expiry batch.
  """
  @spec expire(Service.t(), Context.t(), keyword()) :: result(Expiry.t())
  def expire(service, context, options \\ [])

  def expire(%Service{} = service, %Context{} = context, options) do
    with :ok <- valid_context(context, :expire),
         :ok <- valid_options(options, [:limit, :strategy], :expire),
         {:ok, limit} <- expiry_limit(service, options),
         {:ok, strategy} <- expiry_strategy(service, options),
         :ok <- authorize(service, context, :expire, :collection),
         {:ok, cutoff} <- now(service, :expire),
         {:ok, entries} <- expire_entries(service, cutoff, limit, strategy, context),
         :ok <- valid_expiry_entries(entries, cutoff, limit, strategy) do
      {:ok, %Expiry{strategy: strategy, cutoff: cutoff, entries: entries}}
    end
  end

  def expire(_, _, _),
    do: {:error, Error.new(:invalid_request, :validation, :expire)}

  @doc """
  Returns the directory's own well-known Introduction value without invoking a
  consumer port.
  """
  @spec introduction(Service.t()) :: result(Wotex.Directory.Introduction.t())
  def introduction(%Service{} = service), do: {:ok, service.introduction}

  def introduction(_),
    do: {:error, Error.new(:invalid_service, :configuration, :introduction)}

  defp register_identified(
         service,
         thing_description,
         identifier,
         :anonymous,
         registration_input,
         now,
         context
       ) do
    with {:ok, registration} <- Registration.create(now, registration_input, :register),
         {:ok, entry} <- Entry.new(identifier, thing_description, registration),
         {:ok, stored} <- insert_entry(service, entry, context, :register) do
      {:ok, %Mutation{operation: :register, status: :created, entry: stored}}
    end
  end

  defp register_identified(
         service,
         thing_description,
         identifier,
         :named,
         registration_input,
         now,
         context
       ) do
    case fetch_optional(service, identifier, context, :register) do
      :not_found ->
        with {:ok, registration} <- Registration.create(now, registration_input, :register),
             {:ok, entry} <- Entry.new(identifier, thing_description, registration),
             {:ok, stored} <- insert_entry(service, entry, context, :register) do
          {:ok, %Mutation{operation: :register, status: :created, entry: stored}}
        end

      {:ok, existing} ->
        with {:ok, registration} <-
               Registration.refresh(existing.registration, now, registration_input, :register),
             {:ok, entry} <-
               Entry.new(identifier, thing_description, registration,
                 version: existing.version + 1,
                 state: :active
               ),
             {:ok, stored} <-
               replace_entry(service, entry, existing.version, context, :register) do
          {:ok, %Mutation{operation: :register, status: :replaced, entry: stored}}
        end

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp ensure_identifier(service, thing_description, operation) do
    case ThingDescriptions.id(thing_description) do
      nil ->
        with {:ok, identifier} <- generate_identifier(service, operation),
             {:ok, identified} <-
               ThingDescriptions.put_id(
                 thing_description,
                 identifier,
                 service.thing_description_options,
                 operation
               ) do
          {:ok, identified, identifier, :anonymous}
        end

      identifier when is_binary(identifier) ->
        with :ok <- valid_identifier(identifier, operation) do
          {:ok, thing_description, identifier, :named}
        end
    end
  end

  defp authorize_registration_target(_, _, _, :anonymous), do: :ok

  defp authorize_registration_target(service, context, identifier, :named) do
    authorize(service, context, :register, {:entry, identifier})
  end

  defp registration_input(extracted, options, operation) do
    case {extracted, Keyword.fetch(options, :registration)} do
      {input, :error} ->
        {:ok, input}

      {:absent, {:ok, value}} when is_map(value) ->
        {:ok, {:present, value}}

      {{:present, _}, {:ok, _}} ->
        {:error, Error.new(:invalid_request, :validation, operation)}

      {_, {:ok, _}} ->
        {:error, Error.new(:invalid_request, :validation, operation)}
    end
  end

  defp merge_patch(service, existing, merge_patch) do
    if Registration.server_field_patch?(merge_patch) do
      {:error, Error.new(:invalid_request, :patch, :patch, path: "/registration")}
    else
      existing.thing_description
      |> ThingDescriptions.enriched_map(existing.registration)
      |> MergePatch.apply(merge_patch,
        max_depth: service.max_patch_depth,
        max_nodes: service.max_patch_nodes
      )
    end
  end

  defp expected_version(existing, options, operation) do
    case Keyword.fetch(options, :if_version) do
      :error ->
        {:ok, existing.version}

      {:ok, version} when is_integer(version) and version > 0 and version == existing.version ->
        {:ok, version}

      {:ok, version} when is_integer(version) and version > 0 ->
        {:error,
         Error.new(:conflict, :repository, operation,
           identifier: existing.identifier,
           details: %{expected_version: version}
         )}

      {:ok, _} ->
        {:error,
         Error.new(:invalid_request, :validation, operation, identifier: existing.identifier)}
    end
  end

  defp valid_context(context, operation) do
    if Context.valid?(context),
      do: :ok,
      else: {:error, Error.new(:invalid_context, :validation, operation)}
  end

  defp valid_options(options, allowed, operation) do
    if is_list(options) and Keyword.keyword?(options) and
         Enum.all?(Keyword.keys(options), &(&1 in allowed)) do
      :ok
    else
      {:error, Error.new(:invalid_request, :validation, operation)}
    end
  end

  defp valid_identifier(identifier, operation) do
    if Identifier.valid?(identifier),
      do: :ok,
      else: {:error, Error.new(:invalid_request, :validation, operation)}
  end

  defp matching_identifier(identifier, identifier, _), do: :ok

  defp matching_identifier(identifier, _, operation) do
    {:error, Error.new(:identifier_mismatch, :validation, operation, identifier: identifier)}
  end

  defp valid_patch(patch) when is_map(patch), do: :ok
  defp valid_patch(_), do: {:error, Error.new(:invalid_request, :patch, :patch)}

  defp active(entry, now, operation) do
    if Entry.active?(entry, now),
      do: :ok,
      else: {:error, Error.new(:expired, :expiry, operation, identifier: entry.identifier)}
  end

  defp authorize(service, context, operation, target) do
    {module, state} = service.authorization

    case module.authorize(state, context.principal, operation, target, context.authorization) do
      :ok ->
        :ok

      :deny ->
        {:error,
         Error.new(:forbidden, :authorization, operation, identifier: target_identifier(target))}

      {:error, :forbidden} ->
        {:error,
         Error.new(:forbidden, :authorization, operation, identifier: target_identifier(target))}

      {:error, _} ->
        {:error,
         Error.new(:authorization_failure, :authorization, operation,
           identifier: target_identifier(target)
         )}

      _ ->
        {:error,
         Error.new(:authorization_failure, :authorization, operation,
           identifier: target_identifier(target)
         )}
    end
  end

  defp now(service, operation) do
    {module, state} = service.clock

    case module.now(state) do
      {:ok, %DateTime{} = now} -> {:ok, now}
      {:error, _} -> {:error, Error.new(:clock_failure, :clock, operation)}
      _ -> {:error, Error.new(:clock_failure, :clock, operation)}
    end
  end

  defp generate_identifier(service, operation) do
    {module, state} = service.identifier

    case module.generate(state) do
      {:ok, identifier} ->
        if Identifier.valid?(identifier) do
          {:ok, identifier}
        else
          {:error, Error.new(:identifier_failure, :identifier, operation)}
        end

      {:error, _} ->
        {:error, Error.new(:identifier_failure, :identifier, operation)}

      _ ->
        {:error, Error.new(:identifier_failure, :identifier, operation)}
    end
  end

  defp fetch(service, identifier, context, operation) do
    case fetch_optional(service, identifier, context, operation) do
      {:ok, entry} ->
        {:ok, entry}

      :not_found ->
        {:error, Error.new(:not_found, :repository, operation, identifier: identifier)}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp fetch_optional(service, identifier, context, operation) do
    {module, state} = service.repository

    case module.fetch(state, identifier, context.repository) do
      {:ok, %Entry{} = entry} -> validate_repository_entry(entry, identifier, operation)
      :not_found -> :not_found
      {:error, :not_found} -> :not_found
      {:error, _} -> repository_error(operation, identifier)
      _ -> repository_error(operation, identifier)
    end
  end

  defp insert_entry(service, entry, context, operation) do
    {module, state} = service.repository
    storage_entry = Entry.for_storage(entry)

    case module.insert(state, storage_entry, context.repository) do
      {:ok, %Entry{} = stored} -> validate_stored_entry(stored, storage_entry, operation)
      {:error, :already_exists} -> conflict(operation, entry.identifier)
      {:error, :conflict} -> conflict(operation, entry.identifier)
      {:error, _} -> repository_error(operation, entry.identifier)
      _ -> repository_error(operation, entry.identifier)
    end
  end

  defp replace_entry(service, entry, expected_version, context, operation) do
    {module, state} = service.repository
    storage_entry = Entry.for_storage(entry)

    case module.replace(state, storage_entry, expected_version, context.repository) do
      {:ok, %Entry{} = stored} ->
        validate_stored_entry(stored, storage_entry, operation)

      {:error, :conflict} ->
        conflict(operation, entry.identifier)

      {:error, :not_found} ->
        {:error, Error.new(:not_found, :repository, operation, identifier: entry.identifier)}

      {:error, _} ->
        repository_error(operation, entry.identifier)

      _ ->
        repository_error(operation, entry.identifier)
    end
  end

  defp delete_entry(service, identifier, expected_version, context) do
    {module, state} = service.repository

    case module.delete(state, identifier, expected_version, context.repository) do
      :ok ->
        :ok

      {:error, :conflict} ->
        conflict(:delete, identifier)

      {:error, :not_found} ->
        {:error, Error.new(:not_found, :repository, :delete, identifier: identifier)}

      {:error, _} ->
        repository_error(:delete, identifier)

      _ ->
        repository_error(:delete, identifier)
    end
  end

  defp listing_cursor(%Query{cursor: nil}), do: {:ok, nil}
  defp listing_cursor(%Query{cursor: cursor}), do: Cursor.decode(cursor)

  defp list_entries(service, query, cursor, active_at, context) do
    {module, state} = service.repository

    case module.list(state, query, cursor, active_at, context.repository) do
      {:ok, %Page{} = page} ->
        {:ok, page}

      {:error, :collection_changed} ->
        {:error, Error.new(:collection_changed, :listing, :list)}

      {:error, _} ->
        repository_error(:list, nil)

      _ ->
        repository_error(:list, nil)
    end
  end

  defp expire_entries(service, cutoff, limit, strategy, context) do
    {module, state} = service.repository

    case module.expire_due(state, cutoff, limit, strategy, context.repository) do
      {:ok, entries} when is_list(entries) -> {:ok, entries}
      {:error, _} -> repository_error(:expire, nil)
      _ -> repository_error(:expire, nil)
    end
  end

  defp validate_repository_entry(entry, identifier, operation) do
    if Entry.valid?(entry) and entry.identifier == identifier do
      {:ok, entry}
    else
      repository_error(operation, identifier)
    end
  end

  defp validate_stored_entry(stored, expected, operation) do
    case validate_repository_entry(stored, expected.identifier, operation) do
      {:ok, valid} when valid == expected -> {:ok, valid}
      _ -> repository_error(operation, expected.identifier)
    end
  end

  defp expiry_limit(service, options) do
    limit = Keyword.get(options, :limit, service.default_expiry_batch_limit)

    if is_integer(limit) and limit > 0 and limit <= service.max_expiry_batch_limit do
      {:ok, limit}
    else
      {:error, Error.new(:invalid_request, :validation, :expire)}
    end
  end

  defp expiry_strategy(service, options) do
    case Keyword.get(options, :strategy, service.expiry_strategy) do
      strategy when strategy in [:purge, :retain] -> {:ok, strategy}
      _ -> {:error, Error.new(:invalid_request, :validation, :expire)}
    end
  end

  defp valid_expiry_entries(entries, cutoff, limit, strategy) do
    identifiers =
      Enum.map(entries, fn
        %Entry{identifier: identifier} -> identifier
        _ -> nil
      end)

    valid? =
      length(entries) <= limit and identifiers == Enum.sort(identifiers) and
        length(identifiers) == length(Enum.uniq(identifiers)) and
        Enum.all?(entries, &valid_expiry_entry?(&1, cutoff, strategy))

    if valid?, do: :ok, else: repository_error(:expire, nil)
  end

  defp valid_expiry_entry?(%Entry{} = entry, cutoff, strategy) do
    case validate_repository_entry(entry, entry.identifier, :expire) do
      {:ok, valid} ->
        Registration.expired?(valid.registration, cutoff) and
          (strategy == :purge or valid.state == :expired)

      {:error, _} ->
        false
    end
  end

  defp valid_expiry_entry?(_, _, _), do: false

  defp conflict(operation, identifier) do
    {:error, Error.new(:conflict, :repository, operation, identifier: identifier)}
  end

  defp repository_error(operation, identifier) do
    {:error, Error.new(:repository_failure, :repository, operation, identifier: identifier)}
  end

  defp target_identifier({:entry, identifier}), do: identifier
  defp target_identifier(:collection), do: nil

  defp safe_identifier(identifier) when is_binary(identifier), do: identifier
  defp safe_identifier(_), do: nil
end
