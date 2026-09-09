defmodule Wotex.Directory.Service do
  @moduledoc """
  Immutable configuration for one consumer-owned directory instance.

  Construction validates ports and limits without invoking a callback or
  performing I/O. Every bound is a positive integer; an invalid bound is
  rejected with `invalid_service` and is never silently replaced by a default.

  `thing_description_options` accepts only the core limit vocabulary
  `:max_bytes`, `:max_depth`, `:max_nodes`, `:max_string_bytes`, and
  `:max_collection_size`, and passes it unchanged to the `wotex` core facade.

  A service records explicit repository, authorization, identifier, and clock
  ports together with expiry and listing policy. It owns no process and opens no
  storage connection; the consumer places any stateful adapter under its own
  supervision tree.
  """

  alias Wotex.Directory.{Error, Introduction}

  @repository_callbacks [fetch: 3, insert: 3, replace: 4, delete: 4, list: 5, expire_due: 5]
  @authorization_callbacks [authorize: 5]
  @clock_callbacks [now: 1]
  @identifier_callbacks [generate: 1]
  @thing_description_limits [
    :max_bytes,
    :max_depth,
    :max_nodes,
    :max_string_bytes,
    :max_collection_size
  ]

  @enforce_keys [:repository, :authorization, :clock, :identifier, :introduction]
  defstruct [
    :repository,
    :authorization,
    :clock,
    :identifier,
    :introduction,
    default_page_limit: 50,
    max_page_limit: 200,
    default_expiry_batch_limit: 100,
    max_expiry_batch_limit: 1_000,
    expiry_strategy: :purge,
    max_patch_depth: 64,
    max_patch_nodes: 100_000,
    thing_description_options: []
  ]

  @type port_config :: {module(), term()}
  @type t :: %__MODULE__{
          repository: port_config(),
          authorization: port_config(),
          clock: port_config(),
          identifier: port_config(),
          introduction: Introduction.t(),
          default_page_limit: pos_integer(),
          max_page_limit: pos_integer(),
          default_expiry_batch_limit: pos_integer(),
          max_expiry_batch_limit: pos_integer(),
          expiry_strategy: :purge | :retain,
          max_patch_depth: pos_integer(),
          max_patch_nodes: pos_integer(),
          thing_description_options: keyword()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  @doc "Builds validated, immutable directory configuration from explicit ports."
  def new(options) when is_list(options) do
    with :ok <- validate_option_keys(options),
         {:ok, repository} <- fetch_port(options, :repository, @repository_callbacks),
         {:ok, authorization} <-
           fetch_port(options, :authorization, @authorization_callbacks),
         {:ok, clock} <- fetch_port(options, :clock, @clock_callbacks),
         {:ok, identifier} <- fetch_port(options, :identifier, @identifier_callbacks),
         {:ok, introduction} <- fetch_introduction(options),
         {:ok, bounds} <- validate_bounds(options),
         {:ok, strategy} <- validate_strategy(options),
         {:ok, td_options} <- validate_thing_description_options(options) do
      {:ok,
       struct!(__MODULE__,
         repository: repository,
         authorization: authorization,
         clock: clock,
         identifier: identifier,
         introduction: introduction,
         default_page_limit: bounds.default_page_limit,
         max_page_limit: bounds.max_page_limit,
         default_expiry_batch_limit: bounds.default_expiry_batch_limit,
         max_expiry_batch_limit: bounds.max_expiry_batch_limit,
         expiry_strategy: strategy,
         max_patch_depth: bounds.max_patch_depth,
         max_patch_nodes: bounds.max_patch_nodes,
         thing_description_options: td_options
       )}
    end
  end

  def new(_), do: invalid_service()

  defp validate_option_keys(options) do
    allowed = [
      :repository,
      :authorization,
      :clock,
      :identifier,
      :introduction,
      :default_page_limit,
      :max_page_limit,
      :default_expiry_batch_limit,
      :max_expiry_batch_limit,
      :expiry_strategy,
      :max_patch_depth,
      :max_patch_nodes,
      :thing_description_options
    ]

    if Keyword.keyword?(options) and Enum.all?(Keyword.keys(options), &(&1 in allowed)) do
      :ok
    else
      invalid_service()
    end
  end

  defp fetch_port(options, key, callbacks) do
    case Keyword.fetch(options, key) do
      {:ok, {module, state}} when is_atom(module) ->
        if Code.ensure_loaded?(module) and callbacks_available?(module, callbacks) do
          {:ok, {module, state}}
        else
          invalid_service(%{port: key})
        end

      _ ->
        invalid_service(%{port: key})
    end
  end

  defp callbacks_available?(module, callbacks) do
    Enum.all?(callbacks, fn {name, arity} -> function_exported?(module, name, arity) end)
  end

  defp fetch_introduction(options) do
    case Keyword.fetch(options, :introduction) do
      {:ok, value} -> Introduction.new(value)
      :error -> invalid_service(%{field: :introduction})
    end
  end

  defp validate_bounds(options) do
    bounds = %{
      default_page_limit: Keyword.get(options, :default_page_limit, 50),
      max_page_limit: Keyword.get(options, :max_page_limit, 200),
      default_expiry_batch_limit: Keyword.get(options, :default_expiry_batch_limit, 100),
      max_expiry_batch_limit: Keyword.get(options, :max_expiry_batch_limit, 1_000),
      max_patch_depth: Keyword.get(options, :max_patch_depth, 64),
      max_patch_nodes: Keyword.get(options, :max_patch_nodes, 100_000)
    }

    if Enum.all?(bounds, fn {_, value} -> is_integer(value) and value > 0 end) and
         bounds.default_page_limit <= bounds.max_page_limit and
         bounds.default_expiry_batch_limit <= bounds.max_expiry_batch_limit do
      {:ok, bounds}
    else
      invalid_service(%{field: :bounds})
    end
  end

  defp validate_strategy(options) do
    case Keyword.get(options, :expiry_strategy, :purge) do
      strategy when strategy in [:purge, :retain] -> {:ok, strategy}
      _ -> invalid_service(%{field: :expiry_strategy})
    end
  end

  defp validate_thing_description_options(options) do
    case Keyword.get(options, :thing_description_options, []) do
      value when is_list(value) ->
        if Keyword.keyword?(value) and
             Enum.all?(Keyword.keys(value), &(&1 in @thing_description_limits)) and
             Enum.all?(value, fn {_, limit} -> is_integer(limit) and limit > 0 end) do
          {:ok, value}
        else
          invalid_service(%{field: :thing_description_options})
        end

      _ ->
        invalid_service(%{field: :thing_description_options})
    end
  end

  defp invalid_service(details \\ %{}) do
    {:error, Error.new(:invalid_service, :configuration, :service, details: details)}
  end
end
