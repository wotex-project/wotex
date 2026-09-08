defmodule Wotex.CoAP.Blockwise do
  @moduledoc "Bounded RFC 7959 whole-body transfers over a caller-owned serial exchange function."

  alias Wotex.CoAP.{Block, Codec, Error, Message}
  @sizes [16, 32, 64, 128, 256, 512, 1024]
  @type result :: {:ok, Message.t()} | {:error, Error.t()}

  @doc "Validates the explicit body, block size and exchange-count budgets."
  @spec config(term()) :: {:ok, map()} | {:error, Error.t()}
  def config(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      keys = Keyword.keys(opts)
      size = Keyword.get(opts, :block_size, 512)
      limit = Keyword.get(opts, :max_body_size, 1_048_576)
      blocks = Keyword.get(opts, :max_blocks, 4096)

      if keys -- [:block_size, :max_body_size, :max_blocks] == [] and
           length(keys) == MapSet.size(MapSet.new(keys)) and size in @sizes and
           is_integer(limit) and limit in 1..1_048_576 and
           is_integer(blocks) and blocks in 1..4096 do
        {:ok, %{size: size, limit: limit, blocks: blocks}}
      else
        failure(:invalid_transfer_options)
      end
    else
      failure(:invalid_transfer_options)
    end
  end

  def config(_), do: failure(:invalid_transfer_options)

  @doc "Runs an entire transfer without interleaving; the callback enforces one absolute deadline."
  @spec run(Message.t(), keyword(), state, (Message.t(), state -> {result(), state})) ::
          {result(), state}
        when state: var
  def run(message, opts, state, exchange) do
    with {:ok, config} <- config(opts),
         :ok <- validate(message, config) do
      context = %{exchange: exchange, state: state, left: config.blocks, config: config}
      {result, context} = start(message, context)
      {effect(result, message.code), context.state}
    else
      error -> {error, state}
    end
  end

  defp validate(%Message{} = message, config) do
    with :ok <- Codec.validate_options(message),
         {:ok, _} <- Codec.encode(%{message | payload: <<>>}) do
      cond do
        byte_size(message.payload) > config.limit ->
          failure(:body_limit)

        Enum.any?([23, 27, 28, 60, 292], &(Codec.option(message, &1) != [])) ->
          failure(:managed_block_option)

        message.code not in 1..4 ->
          failure(:invalid_request)

        true ->
          :ok
      end
    end
  end

  defp start(message, context) do
    if byte_size(message.payload) > context.config.size do
      if message.code in [2, 3] do
        message = put_option(message, 292, message.token)
        upload(message, 0, context.config.size, context)
      else
        {failure(:invalid_blockwise_method), context}
      end
    else
      request = put_block(message, 23, 0, false, context.config.size)
      {result, context} = exchange(request, context)
      download(result, message, nil, <<>>, context)
    end
  end

  defp upload(message, offset, size, context) do
    count = min(size, byte_size(message.payload) - offset)
    more = offset + count < byte_size(message.payload)
    number = div(offset, size)

    request =
      message
      |> Map.put(:payload, binary_part(message.payload, offset, count))
      |> put_block(27, number, more, size)
      |> put_option(60, Codec.uint(byte_size(message.payload)))
      |> without_if_none_match(offset)

    {result, context} = exchange(request, context)

    with {:ok, reply} <- result,
         :ok <- success(reply),
         {:ok, block} <- block(reply, 27),
         :ok <- upload_ack(reply, block, number, size, more) do
      if more do
        upload(message, offset + count, block.size, context)
      else
        download({:ok, reply}, message, nil, <<>>, context)
      end
    else
      error -> {error, context}
    end
  end

  defp upload_ack(reply, block, number, size, more) do
    cond do
      block.number != number or block.size > size ->
        failure(:block_ack_mismatch)

      more and
          (reply.code != 95 or not block.more or reply.payload != <<>> or
             Codec.option(reply, 23) != []) ->
        failure(:non_atomic_block_write)

      not more and (block.more or reply.code == 95) ->
        failure(:incomplete_block_write)

      true ->
        :ok
    end
  end

  defp download({:error, _} = error, _, _, _, context), do: {error, context}

  defp download({:ok, reply}, request, previous, acc, context) do
    case Codec.option(reply, 23) do
      [] when is_nil(previous) -> finish(reply, reply.payload, context)
      [] -> {failure(:missing_block), context}
      [_] -> append(reply, request, previous, acc, context)
    end
  end

  defp append(reply, request, previous, acc, context) do
    with :ok <- success(reply),
         {:ok, block} <- block(reply, 23),
         :ok <- representation(reply, block, previous, context.config),
         {:ok, body, status} <- Block.append(acc, block, reply.payload, context.config.limit) do
      if status == :complete do
        finish(reply, body, context)
      else
        continuation =
          request
          |> Map.put(:payload, <<>>)
          |> drop_options([5, 6, 27, 60])
          |> put_block(23, div(byte_size(body), block.size), false, block.size)

        {result, context} = exchange(continuation, context)
        previous = %{reply: reply, size: block.size}
        download(result, request, previous, body, context)
      end
    else
      error -> {error, context}
    end
  end

  defp representation(reply, block, previous, config) do
    maximum = if previous, do: previous.size, else: config.size

    cond do
      block.size != maximum and not is_nil(previous) ->
        failure(:block_size_changed)

      block.size > maximum ->
        failure(:invalid_block_size)

      Enum.any?(Codec.option(reply, 28), &(:binary.decode_unsigned(&1) > config.limit)) ->
        failure(:body_limit)

      previous && identity(reply) != identity(previous.reply) ->
        failure(:representation_changed)

      true ->
        :ok
    end
  end

  defp identity(reply),
    do:
      {reply.code, Codec.option(reply, 4),
       Enum.map(Codec.option(reply, 12), &:binary.decode_unsigned/1)}

  defp finish(reply, body, context) do
    if byte_size(body) <= context.config.limit do
      {{:ok, %{drop_options(reply, [23, 27]) | payload: body}}, context}
    else
      {failure(:body_limit), context}
    end
  end

  defp exchange(_, %{left: 0} = context), do: {failure(:block_limit), context}

  defp exchange(message, context) do
    {result, state} = context.exchange.(message, context.state)
    {result, %{context | state: state, left: context.left - 1}}
  end

  defp block(message, number) do
    case Codec.option(message, number) do
      [value] -> Block.decode(value)
      _ -> failure(:missing_block)
    end
  end

  defp put_block(message, option, number, more, size) do
    {:ok, value} = Block.encode(%Block{number: number, more: more, size: size})
    put_option(message, option, value)
  end

  defp put_option(message, number, value),
    do: %{message | options: [{number, value} | drop_options(message, [number]).options]}

  defp drop_options(message, numbers),
    do: %{message | options: Enum.reject(message.options, &(elem(&1, 0) in numbers))}

  defp without_if_none_match(message, 0), do: message
  defp without_if_none_match(message, _), do: drop_options(message, [5])
  defp success(%{code: code}) when code in 64..95, do: :ok
  defp success(%{code: code}), do: {:error, Error.new(:remote_response, nil, %{code: code})}

  defp effect({:error, error}, code) when code in [2, 3, 4],
    do: {:error, %{error | effect: :unknown}}

  defp effect(result, _), do: result
  defp failure(code), do: {:error, Error.new(code)}
end
