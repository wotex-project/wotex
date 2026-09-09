defmodule Wotex.CoAP.ContractFixture do
  @moduledoc false

  alias Wotex.CoAP
  alias Wotex.CoAP.{Codec, Error, Message, Observe}
  @types %{"con" => :con, "non" => :non, "ack" => :ack, "rst" => :rst}
  @keys %{"method" => :method, "path" => :path, "accept" => :accept}
  @methods %{"get" => :get, "post" => :post, "put" => :put, "delete" => :delete}

  @doc false
  @spec run(map()) :: term()
  def run(%{"operation" => "codec.encode", "input" => input}) do
    case Codec.encode(message(input["message"])) do
      {:ok, bytes} -> %{"status" => "ok", "hex" => hex(bytes)}
      error -> project(error)
    end
  end

  def run(%{"operation" => "codec.decode", "input" => input}),
    do: project(Codec.decode(bytes(input["hex"])))

  def run(%{"operation" => "codec.validate", "input" => input}),
    do: project(Codec.validate_options(message(input["message"])))

  def run(%{"operation" => "message.new", "input" => input}) do
    request =
      Map.new(input, fn {key, value} ->
        {Map.fetch!(@keys, key), if(key == "method", do: Map.fetch!(@methods, value), else: value)}
      end)

    project(CoAP.message(request))
  end

  def run(%{"operation" => "observe.fresh", "input" => input}),
    do: Observe.fresh?(input["previous"], input["current"], input["elapsed_ms"])

  defp message(input) do
    %Message{
      type: Map.fetch!(@types, input["type"]),
      code: input["code"],
      message_id: input["message_id"],
      token: bytes(input["token_hex"]),
      options: Enum.map(input["options"], fn [number, value] -> {number, bytes(value)} end),
      payload: bytes(input["payload_hex"])
    }
  end

  defp project(:ok), do: %{"status" => "ok"}

  defp project({:ok, %Message{} = message}) do
    %{
      "status" => "ok",
      "value" => %{
        "type" => Atom.to_string(message.type),
        "code" => message.code,
        "message_id" => message.message_id,
        "token_hex" => hex(message.token),
        "options" => Enum.map(message.options, fn {number, value} -> [number, hex(value)] end),
        "payload_hex" => hex(message.payload)
      }
    }
  end

  defp project({:error, %Error{} = error}) do
    fields =
      error
      |> Map.take([:code, :field, :details, :retryable, :effect])
      |> Jason.encode!()
      |> Jason.decode!()

    %{"status" => "error", "error" => fields}
  end

  defp bytes(value), do: Base.decode16!(value, case: :lower)
  defp hex(value), do: Base.encode16(value, case: :lower)
end
