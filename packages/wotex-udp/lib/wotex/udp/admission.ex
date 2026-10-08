defmodule Wotex.UDP.Admission do
  @moduledoc false

  alias Wotex.UDP.Error

  @opaque t :: :ets.tid()
  @type request :: %{
          id: reference(),
          from: {pid(), reference()},
          operation: atom(),
          args: list(),
          deadline: integer(),
          epoch: reference()
        }

  @typep state :: %{
           max_calls: pos_integer(),
           max_bytes: pos_integer(),
           bytes: non_neg_integer(),
           sequence: non_neg_integer(),
           notification: reference(),
           notified: boolean(),
           closing: boolean(),
           requests: %{optional(reference()) => map()}
         }

  @doc false
  @spec new(pos_integer(), pos_integer(), reference()) :: t()
  def new(max_calls, max_bytes, notification) do
    table = :ets.new(__MODULE__, [:set, :public])
    true = is_reference(table)

    true =
      :ets.insert(
        table,
        {:state,
         %{
           max_calls: max_calls,
           max_bytes: max_bytes,
           bytes: 0,
           sequence: 0,
           notification: notification,
           notified: false,
           closing: false,
           requests: %{}
         }}
      )

    table
  end

  @doc false
  @spec enqueue(t(), request()) :: {:ok, reference() | nil} | {:error, Error.t()}
  def enqueue(table, request) do
    if valid_request?(request), do: reserve(table, request, 64), else: invalid()
  catch
    :error, :badarg -> invalid()
  end

  @doc false
  @spec take(t(), reference()) :: [map()]
  def take(table, notification) do
    published =
      mutate(table, fn state ->
        {new, retained} = Enum.split_with(state.requests, fn {_, item} -> not item.claimed end)

        requests =
          Map.new(retained ++ Enum.map(new, fn {id, item} -> {id, %{item | claimed: true}} end))

        updated = %{state | requests: requests, notification: notification, notified: false}

        published =
          new
          |> Enum.map(&elem(&1, 1))
          |> Enum.sort_by(& &1.sequence)

        {updated, published}
      end)

    true = is_list(published)
    published
  end

  @doc false
  @spec release(t(), reference()) :: :ok
  def release(table, id) do
    :ok =
      mutate(table, fn state ->
        case Map.pop(state.requests, id) do
          {nil, _} ->
            {state, :ok}

          {request, remaining} ->
            {%{
               state
               | requests: remaining,
                 bytes: state.bytes - bytes(request),
                 closing: state.closing and request.operation != :close
             }, :ok}
        end
      end)
  end

  @doc false
  @spec usage(t()) :: non_neg_integer()
  def usage(table) do
    state = read(table)
    map_size(state.requests) * (state.max_bytes + 1) + state.bytes
  catch
    :error, :badarg -> 0
  end

  defp reserve(_, _, 0), do: error(:overload)

  defp reserve(table, request, attempts) do
    state = read(table)
    size = bytes(request)

    cond do
      state.closing ->
        error(:closed)

      map_size(state.requests) >= state.max_calls or state.bytes + size > state.max_bytes ->
        error(:overload)

      poll?(request) and map_size(state.requests) > 0 ->
        error(:timeout)

      Map.has_key?(state.requests, request.id) ->
        invalid()

      true ->
        item = Map.merge(request, %{sequence: state.sequence + 1, claimed: false})

        updated = %{
          state
          | requests: Map.put(state.requests, request.id, item),
            bytes: state.bytes + size,
            sequence: item.sequence,
            closing: request.operation == :close,
            notified: true
        }

        if replace(table, state, updated) do
          {:ok, if(state.notified, do: nil, else: state.notification)}
        else
          reserve(table, request, attempts - 1)
        end
    end
  end

  # Only the owner takes/releases entries. Racing producer changes only add an
  # entry, so at most max_calls successful insertions can delay an owner update.
  @spec mutate(t(), (state() -> {state(), result})) :: result when result: term()
  defp mutate(table, function) do
    state = read(table)
    {updated, result} = function.(state)
    if replace(table, state, updated), do: result, else: mutate(table, function)
  end

  @spec read(t()) :: state()
  defp read(table) do
    [{:state, state}] = :ets.lookup(table, :state)
    state
  end

  defp replace(table, old, new),
    do:
      :ets.select_replace(table, [
        {{:state, :"$1"}, [{:"=:=", :"$1", {:const, old}}], [{:const, {:state, new}}]}
      ]) == 1

  defp valid_request?(
         %{
           id: id,
           from: {caller, reply},
           operation: operation,
           args: args,
           deadline: deadline,
           epoch: epoch
         } = request
       ) do
    map_size(request) == 6 and is_reference(id) and is_pid(caller) and node(caller) == node() and
      is_reference(reply) and
      operation in [:local, :send, :recv, :recv_batch, :join, :leave, :close] and
      is_list(args) and length(args) <= 3 and is_integer(deadline) and is_reference(epoch) and
      (operation != :send or match?([_, data, _] when is_binary(data), args))
  end

  defp valid_request?(_), do: false

  defp poll?(%{operation: operation, args: args}),
    do: operation in [:send, :recv, :recv_batch] and List.last(args) == 0

  defp bytes(%{operation: :send, args: [_, data, _]}), do: byte_size(data)
  defp bytes(_), do: 0
  defp invalid, do: error(:invalid_handle)
  defp error(kind), do: {:error, %Error{kind: kind, operation: :admission, reason: nil}}
end
