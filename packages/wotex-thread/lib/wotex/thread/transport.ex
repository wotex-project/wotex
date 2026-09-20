defmodule Wotex.Thread.Transport do
  @moduledoc """
  Executes Wotex Runtime requests through a scoped Thread management session.

  The transport validates the Runtime request, execution context and static
  daemon profile, maps the selected Form through `Wotex.Thread.Mapping`, opens
  the configured client, performs one read-only command, and closes the exact
  session. Subscription callbacks return explicit unsupported errors because
  the profile does not produce application observations or Events.

  ## Runtime boundary

  An exact controller target is required. Forms must omit `contentType`.
  Credentials and security-mode configuration are rejected because this adapter
  defines no credential transport. Runtime Form selection is
  not authorization, and returned network-management data does not establish
  canonical application Property truth. The consumer owns socket access,
  daemon and radio lifecycle, deadlines, authorization, supervision, and
  interpretation of the result.
  """
  @behaviour Wotex.Runtime.Transport
  alias Wotex.Runtime.{Context, ExecutionContext, Request, Result}
  alias Wotex.Thread
  alias Wotex.Thread.{Error, Mapping}

  @impl Wotex.Runtime.Transport
  def request(
        %Request{affordance_type: :property, operation: :readproperty} = request,
        execution,
        config
      ) do
    with {:ok, prepared} <- prepare(request, execution, config) do
      Thread.with_connection(prepared.options, fn session ->
        execute(session, prepared.mapping.message, request, prepared.deadline)
      end)
    end
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_transport_context)}

  @impl Wotex.Runtime.Transport
  def subscribe(_, _, _, _), do: {:error, Error.new(:not_supported)}
  @impl Wotex.Runtime.Transport
  def unsubscribe(_, _, _, _), do: {:error, Error.new(:not_supported)}

  @doc false
  @spec prepare(Request.t(), ExecutionContext.t(), term()) :: {:ok, map()} | {:error, Error.t()}
  def prepare(
        %Request{} = request,
        %ExecutionContext{credential: nil, context: context},
        config
      ) do
    with :ok <- request_context(request, context),
         :ok <- configuration(config),
         :ok <- profile(request),
         {:ok, timeout} <- budget(request.deadline, Keyword.get(config, :timeout, 5000)),
         deadline = now() + timeout,
         {:ok, mapping} <-
           Mapping.command(request.form, request.operation, request.input, request.resolved_href),
         true <- Keyword.get(config, :target) == mapping.target,
         {:ok, remaining} <- remaining(deadline) do
      options =
        config
        |> Keyword.delete(:target)
        |> Keyword.put(:timeout, remaining)

      {:ok, %{mapping: mapping, options: options, deadline: deadline}}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:target_mismatch)}
    end
  end

  def prepare(_, %ExecutionContext{credential: credential}, _) when credential != nil,
    do: {:error, Error.new(:unsupported_security)}

  def prepare(_, _, _), do: {:error, Error.new(:invalid_transport_context)}

  defp request_context(request, %Context{} = context) do
    with {:ok, _} <- Context.new(request_id: request.request_id, deadline: request.deadline),
         true <- request.request_id == Context.request_id(context),
         true <- request.deadline == Context.deadline(context),
         do: :ok,
         else: (_ -> {:error, Error.new(:invalid_transport_context)})
  end

  defp request_context(_, _), do: {:error, Error.new(:invalid_transport_context)}

  defp configuration(config) do
    cond do
      not Keyword.keyword?(config) ->
        {:error, Error.new(:invalid_options)}

      length(Keyword.keys(config)) != length(Enum.uniq(Keyword.keys(config))) ->
        {:error, Error.new(:invalid_options)}

      Keyword.has_key?(config, :security_mode) ->
        {:error, Error.new(:unsupported_security)}

      true ->
        :ok
    end
  end

  defp profile(%Request{profile: profile, operation: :readproperty}) do
    if profile == Thread.profile(),
      do: :ok,
      else: {:error, Error.new(:unsupported_profile)}
  end

  defp profile(_), do: {:error, Error.new(:unsupported_profile)}

  defp execute(session, message, request, deadline) do
    with {:ok, remaining} <- remaining(deadline),
         {:ok, value} <- Thread.send(%{session | timeout: remaining}, message),
         {:ok, value} <- runtime_value(message.type, value),
         {:ok, _} <- remaining(deadline),
         do: Result.new(request.request_id, request.operation, value)
  end

  defp runtime_value(:state, value)
       when value in ["disabled", "detached", "child", "router", "leader"],
       do: {:ok, value}

  defp runtime_value(:version, value) when is_binary(value) do
    if byte_size(value) in 1..1024 and String.valid?(value) and
         not Regex.match?(~r/[\x00-\x1f\x7f]/, value),
       do: {:ok, value},
       else: {:error, Error.new(:invalid_response)}
  end

  defp runtime_value(:network_name, nil), do: {:ok, nil}

  defp runtime_value(:network_name, value) when is_binary(value) do
    if byte_size(value) in 1..16 and String.valid?(value) and
         not Regex.match?(~r/[\x00-\x1f\x7f]/, value),
       do: {:ok, value},
       else: {:error, Error.new(:invalid_response)}
  end

  defp runtime_value(:rloc16, nil), do: {:ok, nil}
  defp runtime_value(:rloc16, value) when is_integer(value) and value in 0..65_535, do: {:ok, value}
  defp runtime_value(_, _), do: {:error, Error.new(:invalid_response)}

  defp remaining(deadline) do
    left = deadline - now()
    if left > 0, do: {:ok, left}, else: {:error, Error.new(:deadline_exceeded)}
  end

  defp budget(deadline, max) when is_integer(max) and max in 1..60_000 do
    now =
      if is_struct(deadline, DateTime),
        do: DateTime.utc_now(),
        else: now()

    case Context.remaining_ms(deadline, now) do
      :infinity -> {:ok, max}
      left when is_integer(left) and left > 0 -> {:ok, min(left, max)}
      _ -> {:error, Error.new(:deadline_exceeded)}
    end
  end

  defp budget(_, _), do: {:error, Error.new(:invalid_timeout)}
  defp now, do: System.monotonic_time(:millisecond)
end
