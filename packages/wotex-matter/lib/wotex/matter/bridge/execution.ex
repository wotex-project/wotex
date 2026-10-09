defmodule Wotex.Matter.Bridge.Execution do
  @moduledoc false

  alias Wotex.Runtime.{Context, ExposedThing}

  @doc false
  @spec run(pid(), pos_integer(), reference(), map(), map(), Context.t(), function()) ::
          :completed | :denied | :failed | :unknown
  def run(owner, id, token, request, route, context, policy) do
    with :ok <- clock(owner, id, token),
         :allow <- safely(fn -> policy.(request, context) end, :failed),
         :ok <- clock(owner, id, token),
         {:ok, input} <- safely(fn -> route.input.(request.payload, context) end, :failed),
         :ok <- clock(owner, id, token) do
      dispatch(owner, id, token, route, input, context)
    else
      :deny -> :denied
      :elapsed -> :unknown
      _ -> :failed
    end
  end

  defp dispatch(owner, id, token, route, input, context) do
    safely(
      fn ->
        result = ExposedThing.dispatch(route.exposed, route.operation, route.name, input, context)

        with :ok <- clock(owner, id, token),
             outcome when outcome in [:completed, :denied, :failed, :unknown] <-
               route.result.(result, context),
             :ok <- clock(owner, id, token) do
          outcome
        else
          _ -> :unknown
        end
      end,
      :unknown
    )
  end

  defp clock(owner, id, token) do
    case GenServer.call(owner, {:execution_clock, id, token}) do
      :ok -> :ok
      _ -> :elapsed
    end
  end

  defp safely(callback, failure) do
    callback.()
  rescue
    _ -> failure
  catch
    _, _ -> failure
  end
end
