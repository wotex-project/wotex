defmodule Wotex.CoAP.Blockwise do
  @moduledoc "Bounded RFC 7959 whole-body transfers over a caller-owned serial exchange function."

  alias Wotex.CoAP.{Block, Codec, Error, Message}
  @sizes [16, 32, 64, 128, 256, 512, 1024]
  @type result :: {:ok, Message.t()} | {:error, Error.t()}

  @doc "Validates the explicit body, block size and exchange-count budgets."
  @spec config(term()) :: {:ok, map()} | {:error, Error.t()}
  def config(opts) do
    with {:ok, values} <- options(opts, %{}) do
      size = Map.get(values, :block_size, 512)
      limit = Map.get(values, :max_body_size, 1_048_576)
      blocks = Map.get(values, :max_blocks, 4096)

      if size in @sizes and is_integer(limit) and limit in 1..1_048_576 and
           is_integer(blocks) and blocks in 1..4096,
         do: {:ok, %{size: size, limit: limit, blocks: blocks}},
         else: failure(:invalid_transfer_options)
    end
  end

  defp options([], values), do: {:ok, values}

  defp options([{key, value} | rest], values)
       when key in [:block_size, :max_body_size, :max_blocks] and not is_map_key(values, key),
       do: options(rest, Map.put(values, key, value))

  defp options(_, _), do: failure(:invalid_transfer_options)

  @doc "Runs an entire transfer without interleaving; the callback enforces one absolute deadline."
  @spec run(Message.t(), keyword(), state, (Message.t(), state -> {result(), state})) ::
          {result(), state}
        when state: var
  def run(message, opts, state, exchange) when is_function(exchange, 2) do
    with {:ok, config} <- config(opts),
         :ok <- validate_request(message, config) do
      context = context(config, state, exchange)
      {result, context} = start(message, context)
      {effect(result, message.code), context.state}
    else
      error -> {error, state}
    end
  end

  def run(_, _, state, _), do: {failure(:invalid_exchange), state}

  @doc "Continues a first report with a distinct GET token, retaining the first report metadata."
  @spec continue(Message.t(), Message.t(), keyword(), state, (Message.t(), state ->
                                                                {result(), state})) ::
          {result(), state}
        when state: var
  def continue(request, first, opts, state, exchange) when is_function(exchange, 2) do
    with {:ok, config} <- config(opts),
         :ok <- validate_continuation_request(request, first, config),
         true <- request.token != first.token do
      context = %{context(config, state, exchange) | first: first, left: config.blocks - 1}
      {result, context} = download({:ok, first}, request, nil, <<>>, context)
      {result, context.state}
    else
      false -> {failure(:continuation_token_conflict), state}
      error -> {error, state}
    end
  end

  def continue(_, _, _, state, _), do: {failure(:invalid_exchange), state}

  @doc "Validates a first response and continuation request before session admission."
  @spec validate_continuation(term(), term(), keyword()) :: :ok | {:error, Error.t()}
  def validate_continuation(request, first, opts) do
    with {:ok, config} <- config(opts),
         do: validate_continuation_request(request, first, config)
  end

  defp validate_continuation_request(request, first, config) do
    with :ok <- validate_request(request, config),
         true <- request.code == 1 and request.payload == <<>>,
         :ok <- Codec.validate_options(first),
         {:ok, _} <- Codec.encode(first),
         :ok <- success(first),
         true <- first.code != 95 do
      first_body(first, config)
    else
      false -> failure(:invalid_continuation)
      error -> error
    end
  end

  defp first_body(first, config) do
    case Codec.option(first, 23) do
      [] ->
        if byte_size(first.payload) <= config.limit and within_size_limit?(first, config.limit),
          do: :ok,
          else: failure(:body_limit)

      [_] ->
        with {:ok, block} <- block(first, 23),
             :ok <- representation(first, block, nil, config),
             {:ok, _, _} <- Block.append(<<>>, block, first.payload, config.limit),
             do: :ok
    end
  end

  defp context(config, state, exchange),
    do: %{exchange: exchange, state: state, left: config.blocks, config: config, first: nil}

  @doc "Validates a complete-body request before allocating any transport resources."
  @spec validate(term(), keyword()) :: :ok | {:error, Error.t()}
  def validate(message, opts) do
    with {:ok, config} <- config(opts), do: validate_request(message, config)
  end

  defp validate_request(%Message{} = message, config) do
    with :ok <- Codec.validate_options(message),
         {:ok, _} <- Codec.encode(%{message | payload: <<>>}) do
      cond do
        byte_size(message.payload) > config.limit ->
          failure(:body_limit)

        Enum.any?([23, 27, 28, 60, 292], &(Codec.option(message, &1) != [])) ->
          failure(:managed_block_option)

        message.code not in 1..4 or message.type not in [:con, :non] ->
          failure(:invalid_request)

        true ->
          :ok
      end
    end
  end

  defp validate_request(_, _), do: failure(:invalid_request)

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

    request =
      if more, do: request, else: put_block(request, 23, 0, false, context.config.size)

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

      not within_size_limit?(reply, config.limit) ->
        failure(:body_limit)

      previous && identity(reply) != identity(previous.reply) ->
        failure(:representation_changed)

      true ->
        :ok
    end
  end

  defp within_size_limit?(reply, limit),
    do: Enum.all?(Codec.option(reply, 28), &(:binary.decode_unsigned(&1) <= limit))

  defp identity(reply),
    do:
      {reply.code, Codec.option(reply, 4),
       Enum.map(Codec.option(reply, 12), &:binary.decode_unsigned/1)}

  defp finish(reply, body, context) do
    with :ok <- success(reply),
         true <- reply.code != 95 do
      if byte_size(body) <= context.config.limit and within_size_limit?(reply, context.config.limit) do
        {{:ok, %{drop_options(context.first || reply, [23, 27]) | payload: body}}, context}
      else
        {failure(:body_limit), context}
      end
    else
      false -> {failure(:incomplete_response), context}
      error -> {error, context}
    end
  end

  defp exchange(_, %{left: 0} = context), do: {failure(:block_limit), context}

  defp exchange(message, context) do
    {result, state} = invoke(context.exchange, message, context.state)
    {result, %{context | state: state, left: context.left - 1}}
  end

  defp invoke(callback, message, state) do
    case callback.(message, state) do
      {{:ok, reply}, next} ->
        with :ok <- Codec.validate_options(reply), {:ok, _} <- Codec.encode(reply) do
          {{:ok, reply}, next}
        else
          error -> {error, next}
        end

      {{:error, %Error{}} = error, next} ->
        {error, next}

      _ ->
        {failure(:invalid_exchange_result), state}
    end
  catch
    _, _ -> {failure(:exchange_failed), state}
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

  defp success(%{code: code}) when code in 128..191,
    do: {:error, Error.new(:remote_response, nil, %{code: code})}

  defp success(_), do: failure(:invalid_response)

  defp effect({:error, error}, code) when code in [2, 3, 4],
    do: {:error, %{error | effect: :unknown}}

  defp effect(result, _), do: result
  defp failure(code), do: {:error, Error.new(code)}
end
