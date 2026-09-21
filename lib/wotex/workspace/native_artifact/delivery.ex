defmodule Wotex.Workspace.NativeArtifact.Delivery do
  @moduledoc """
  Explicit source and prebuilt delivery selection.

  The caller supplies the package-specific source operation and the shared
  prebuilt operation. A prebuilt failure reaches the source callback only for
  `prefer_prebuilt` when that individual invocation enables fallback.
  """

  @type mode :: :source | :prebuilt | :prefer_prebuilt
  @type operation :: (-> {:ok, term()} | {:error, [String.t()]} | {:error, String.t()})

  defmodule Result do
    @moduledoc "The selected and actual delivery paths for a successful operation."

    @enforce_keys [:selected_mode, :actual_mode, :value, :prebuilt_errors]
    defstruct @enforce_keys
  end

  defmodule Failure do
    @moduledoc "A delivery failure that preserves the selected mode and attempted path."

    @enforce_keys [:selected_mode, :actual_mode, :errors, :prebuilt_errors]
    defstruct @enforce_keys
  end

  @doc "Parses the exact delivery-mode names used in descriptors and evidence."
  @spec parse(String.t()) :: {:ok, mode()} | {:error, String.t()}
  def parse("source"), do: {:ok, :source}
  def parse("prebuilt"), do: {:ok, :prebuilt}
  def parse("prefer_prebuilt"), do: {:ok, :prefer_prebuilt}

  def parse(_),
    do: {:error, "delivery mode must be source, prebuilt or prefer_prebuilt"}

  @doc "Runs exactly the selected delivery policy."
  @spec run(mode(), operation(), operation(), keyword()) ::
          {:ok, Result.t()} | {:error, Failure.t()}
  def run(mode, source, prebuilt, opts \\ [])
      when mode in [:source, :prebuilt, :prefer_prebuilt] and is_function(source, 0) and
             is_function(prebuilt, 0) do
    allow_fallback = Keyword.get(opts, :allow_source_fallback, false)

    cond do
      not is_boolean(allow_fallback) ->
        failure(mode, :not_run, ["allow_source_fallback must be a boolean"], [])

      allow_fallback and mode != :prefer_prebuilt ->
        failure(
          mode,
          :not_run,
          ["source fallback is valid only with prefer_prebuilt"],
          []
        )

      mode == :source ->
        run_one(:source, source)

      mode == :prebuilt ->
        run_one(:prebuilt, prebuilt)

      true ->
        prefer_prebuilt(source, prebuilt, allow_fallback)
    end
  end

  defp run_one(mode, operation) do
    case normalize(operation.()) do
      {:ok, value} ->
        {:ok,
         %Result{
           selected_mode: mode,
           actual_mode: mode,
           value: value,
           prebuilt_errors: []
         }}

      {:error, errors} ->
        failure(mode, mode, errors, if(mode == :prebuilt, do: errors, else: []))
    end
  end

  defp prefer_prebuilt(source, prebuilt, allow_fallback) do
    case normalize(prebuilt.()) do
      {:ok, value} ->
        {:ok,
         %Result{
           selected_mode: :prefer_prebuilt,
           actual_mode: :prebuilt,
           value: value,
           prebuilt_errors: []
         }}

      {:error, prebuilt_errors} when allow_fallback ->
        case normalize(source.()) do
          {:ok, value} ->
            {:ok,
             %Result{
               selected_mode: :prefer_prebuilt,
               actual_mode: :source,
               value: value,
               prebuilt_errors: prebuilt_errors
             }}

          {:error, source_errors} ->
            errors =
              Enum.map(prebuilt_errors, &"prebuilt: #{&1}") ++
                Enum.map(source_errors, &"source: #{&1}")

            failure(:prefer_prebuilt, :source, errors, prebuilt_errors)
        end

      {:error, prebuilt_errors} ->
        failure(:prefer_prebuilt, :prebuilt, prebuilt_errors, prebuilt_errors)
    end
  end

  defp normalize({:ok, value}), do: {:ok, value}
  defp normalize({:error, errors}) when is_list(errors), do: {:error, errors}
  defp normalize({:error, error}) when is_binary(error), do: {:error, [error]}
  defp normalize(_), do: {:error, ["delivery operation returned an invalid result"]}

  defp failure(selected, actual, errors, prebuilt_errors) do
    {:error,
     %Failure{
       selected_mode: selected,
       actual_mode: actual,
       errors: errors,
       prebuilt_errors: prebuilt_errors
     }}
  end
end
