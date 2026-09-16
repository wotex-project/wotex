defmodule Wotex.OPCUA.Browse do
  @moduledoc """
  Returns bounded native Browse pages with typed references.

  `references/3` requires an explicitly selected persistent `Open62541`
  Session. It validates the node and strict finite options before service I/O,
  retains all seven ReferenceDescription fields in server order and never
  follows a remote ExpandedNodeId. A continuation belongs to the original
  persistent native Session and must be consumed or released.
  """

  alias Wotex.OPCUA.{Address, Binary, Error, Open62541, Session}
  alias Wotex.OPCUA.Browse.{Continuation, Page}
  alias Wotex.OPCUA.Native.{Config, Host}

  @defaults [
    direction: :forward,
    reference_type_id: "ns=0;i=33",
    include_subtypes: true,
    node_class_mask: 0,
    page_size: 128,
    max_pages: 64,
    max_references: 4096
  ]
  @keys [:timeout_ms | Keyword.keys(@defaults)]

  @doc "Browses one bounded service-level page on the caller-owned persistent native Session."
  @spec references(Session.t(), term(), keyword()) :: {:ok, Page.t()} | {:error, Error.t()}
  def references(session, node, opts \\ [])

  def references(
        %Session{
          client: Open62541,
          handle: %{
            owner: owner,
            config: %Config{lifecycle: :persistent},
            host: host,
            namespace_array: namespaces
          },
          timeout: session_timeout
        },
        node,
        opts
      )
      when owner == self() and is_pid(host) and is_list(namespaces) do
    with {:ok, parameters, timeout, limits} <- options(node, opts, session_timeout),
         {:ok, %{"references" => raw, "status" => status, "continuation" => continuation}} <-
           Host.browse_page(host, parameters, limits, timeout) do
      case typed_references(raw, namespaces) do
        {:ok, references} ->
          {:ok, %Page{references: references, status: status, continuation: continuation}}

        {:error, _} = error ->
          cleanup(host, continuation, session_timeout)
          error
      end
    else
      {:error, _} = error -> error
      _ -> {:error, Error.new(:invalid_native_frame)}
    end
  end

  def references(
        %Session{client: Open62541, handle: %{config: %Config{lifecycle: :oneshot}}},
        _,
        _
      ),
      do: {:error, Error.new(:persistent_session_required)}

  def references(_, _, _), do: {:error, Error.new(:unsupported_protocol)}

  @doc "Consumes one live continuation on the original persistent native Session."
  @spec next(Session.t(), Continuation.t()) :: {:ok, Page.t()} | {:error, Error.t()}
  def next(
        %Session{
          client: Open62541,
          handle: %{
            owner: owner,
            host: host,
            config: %Config{lifecycle: :persistent},
            namespace_array: namespaces
          },
          timeout: timeout
        },
        %Continuation{} = continuation
      )
      when owner == self() and is_pid(host) and is_list(namespaces) do
    with {:ok, %{"references" => raw, "status" => status, "continuation" => following}} <-
           Host.browse_next(host, continuation, timeout) do
      case typed_references(raw, namespaces) do
        {:ok, references} ->
          {:ok, %Page{references: references, status: status, continuation: following}}

        {:error, _} = error ->
          cleanup(host, following, timeout)
          error
      end
    end
  end

  def next(%Session{client: Open62541, handle: %{config: %Config{lifecycle: :oneshot}}}, _),
    do: {:error, Error.new(:persistent_session_required)}

  def next(_, _), do: {:error, Error.new(:invalid_continuation)}

  @doc "Releases one live continuation on the original persistent native Session."
  @spec release(Session.t(), Continuation.t()) :: :ok | {:error, Error.t()}
  def release(
        %Session{
          client: Open62541,
          handle: %{owner: owner, host: host, config: %Config{lifecycle: :persistent}},
          timeout: timeout
        },
        %Continuation{pid: host} = continuation
      )
      when owner == self() and is_pid(host) do
    if Process.alive?(host),
      do: Host.browse_release(host, continuation, timeout),
      else: :ok
  end

  def release(%Session{client: Open62541, handle: %{config: %Config{lifecycle: :oneshot}}}, _),
    do: {:error, Error.new(:persistent_session_required)}

  def release(_, _), do: {:error, Error.new(:invalid_continuation)}

  @doc "Collects complete pages in server order within one original browse deadline."
  @spec all(Session.t(), term(), keyword()) ::
          {:ok, %{references: [Binary.Reference.t()], status: non_neg_integer()}}
          | {:error, Error.t()}
  def all(session, node, opts \\ []) do
    with {:ok, page} <- references(session, node, opts) do
      collect(session, page, [])
    end
  end

  defp collect(session, %Page{status: status, continuation: continuation} = page, prior) do
    if Bitwise.band(status, 0xC000_0000) != 0 do
      cleanup(session.handle.host, continuation, session.timeout)
      {:error, Error.new(:incomplete_browse)}
    else
      accumulated = [page.references | prior]

      case continuation do
        nil ->
          references =
            accumulated
            |> Enum.reverse()
            |> List.flatten()

          {:ok, %{references: references, status: status}}

        handle ->
          with {:ok, following} <- next(session, handle) do
            collect(session, following, accumulated)
          end
      end
    end
  end

  defp cleanup(_, nil, _), do: :ok
  defp cleanup(host, handle, timeout), do: Host.browse_release(host, handle, timeout)

  defp options(node, opts, session_timeout) do
    if Keyword.keyword?(opts) and length(opts) == MapSet.size(MapSet.new(Keyword.keys(opts))) and
         Enum.all?(Keyword.keys(opts), &(&1 in @keys)) do
      opts = Keyword.merge(@defaults, opts)

      with {:ok, id} <- Address.new(node),
           {:ok, reference_type} <- Address.new(opts[:reference_type_id]),
           true <- opts[:direction] in [:forward, :inverse, :both],
           true <- is_boolean(opts[:include_subtypes]),
           true <- is_integer(opts[:node_class_mask]) and opts[:node_class_mask] in 0..255,
           true <- is_integer(opts[:page_size]) and opts[:page_size] in 1..256,
           true <- is_integer(opts[:max_pages]) and opts[:max_pages] in 1..64,
           true <- is_integer(opts[:max_references]) and opts[:max_references] in 1..4096,
           true <- is_integer(session_timeout) and session_timeout in 1..60_000,
           timeout <- Keyword.get(opts, :timeout_ms, session_timeout),
           true <- is_integer(timeout) and timeout in 1..60_000 do
        parameters = %{
          "node_id" => Address.to_string(id),
          "reference_type_id" => Address.to_string(reference_type),
          "direction" => Atom.to_string(opts[:direction]),
          "include_subtypes" => opts[:include_subtypes],
          "node_class_mask" => opts[:node_class_mask],
          "page_size" => opts[:page_size]
        }

        {:ok, parameters, min(timeout, session_timeout),
         %{max_pages: opts[:max_pages], max_references: opts[:max_references]}}
      else
        {:error, _} = error -> error
        _ -> {:error, Error.new(:invalid_value)}
      end
    else
      {:error, Error.new(:invalid_value)}
    end
  end

  defp typed_references(raw, namespaces) do
    Enum.reduce_while(raw, {:ok, []}, fn reference, {:ok, typed} ->
      case typed_reference(reference, namespaces) do
        {:ok, value} -> {:cont, {:ok, [value | typed]}}
        error -> {:halt, error}
      end
    end)
    |> reverse_references()
  end

  defp reverse_references({:ok, references}), do: {:ok, Enum.reverse(references)}
  defp reverse_references(error), do: error

  defp typed_reference(reference, namespaces) do
    value = %{
      reference_type_id: reference["reference_type_id"],
      is_forward: reference["is_forward"],
      node_id: expanded(reference["node_id"]),
      browse_name: name(reference["browse_name"]),
      display_name: display(reference["display_name"]),
      node_class: reference["node_class"],
      type_definition: expanded(reference["type_definition"])
    }

    with {:ok, bytes} <- Binary.encode_reference_description(value),
         {:ok, typed, <<>>} <- Binary.decode_reference_description(bytes),
         true <- local_references?(typed, namespaces) do
      {:ok, typed}
    else
      _ -> {:error, Error.new(:unsupported_remote_reference)}
    end
  end

  defp expanded(value),
    do: %{
      node_id: value["node_id"],
      namespace_uri: value["namespace_uri"],
      server_index: value["server_index"]
    }

  defp name(value), do: %{namespace: value["namespace"], name: value["name"]}
  defp display(value), do: %{locale: value["locale"], text: value["text"]}

  defp local_references?(reference, namespaces) do
    reference.reference_type_id.namespace < length(namespaces) and
      local_expanded?(reference.node_id, namespaces) and
      local_expanded?(reference.type_definition, namespaces)
  end

  defp local_expanded?(%{namespace_uri: nil, server_index: 0, node_id: node}, namespaces),
    do: node.namespace < length(namespaces)

  defp local_expanded?(_, _), do: true
end
