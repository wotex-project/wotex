defmodule Wotex.Runtime.FormSelector do
  @moduledoc """
  Deterministically selects an Interaction Affordance or top-level Thing Form
  by TD order and then supplied profile order.

  No transport is guessed. A profile must declare the exact W3C WoT operation,
  and a Form must declare it or receive it as a TD 1.1 default operation for
  its interaction context through `Wotex.Form.operations/2`. Thing-level Forms
  have no defaults.

  `select/5` handles Property, Action, and Event affordances; `select_thing/3`
  handles top-level Thing operations. Both resolve relative references against
  the validated Thing Description and return a selection value without
  resolving credentials, authorizing the operation, or invoking a transport.
  """

  alias Wotex.{Form, ThingDescription}
  alias Wotex.Runtime.{BindingProfile, Error, Limits, Selection}

  @types %{property: "properties", action: "actions", event: "events"}

  @doc "Selects an Interaction Affordance Form and binding profile."
  @spec select(ThingDescription.t(), atom(), String.t(), atom(), [BindingProfile.t()]) ::
          {:ok, Selection.t()} | {:error, Error.t()}
  def select(%ThingDescription{} = td, type, name, operation, profiles)
      when type in [:property, :action, :event] and is_binary(name) and is_list(profiles) do
    document = ThingDescription.to_map(td)
    interaction = %{type: type, name: name, operation: operation}

    with :ok <- validate_operation(operation, type),
         {:ok, affordance} <- fetch_affordance(document, type, name),
         {:ok, selection} <- choose(document, affordance, interaction, profiles) do
      {:ok, selection}
    end
  end

  def select(_td, _type, _name, _operation, _profiles) do
    {:error, Error.new(:invalid_selection_input, :selection, "selection input is invalid")}
  end

  @doc "Selects a top-level Thing Form and binding profile."
  @spec select_thing(ThingDescription.t(), atom(), [BindingProfile.t()]) ::
          {:ok, Selection.t()} | {:error, Error.t()}
  def select_thing(%ThingDescription{} = td, operation, profiles) when is_list(profiles) do
    document = ThingDescription.to_map(td)
    interaction = %{type: :thing, name: nil, operation: operation}

    with :ok <- validate_operation(operation, :thing),
         {:ok, selection} <- choose(document, document, interaction, profiles) do
      {:ok, selection}
    end
  end

  def select_thing(_td, _operation, _profiles) do
    {:error, Error.new(:invalid_selection_input, :selection, "selection input is invalid")}
  end

  defp validate_operation(operation, type) do
    supported? =
      operation in Wotex.Runtime.operations() and
        Wotex.Runtime.interaction_type(operation) == type

    if supported? do
      :ok
    else
      {:error, Error.new(:unsupported_operation, :selection, "operation is not supported")}
    end
  end

  defp fetch_affordance(document, type, name) do
    case get_in(document, [@types[type], name]) do
      affordance when is_map(affordance) ->
        {:ok, affordance}

      _missing ->
        {:error,
         Error.new(:affordance_not_found, :selection, "Interaction Affordance was not found", %{
           affordance_type: type,
           affordance_name: name
         })}
    end
  end

  defp choose(document, affordance, interaction, profiles) do
    forms = Map.get(affordance, "forms", [])

    with :ok <- validate_candidates(forms, profiles) do
      case find_candidate(forms, profiles, document, affordance, interaction) do
        {form, resolved_href, profile} ->
          {:ok,
           %Selection{
             affordance_type: interaction.type,
             affordance_name: interaction.name,
             affordance: affordance,
             operation: interaction.operation,
             form: form,
             resolved_href: resolved_href,
             profile: profile,
             security: security(document, affordance, Form.to_map(form))
           }}

        nil ->
          {:error,
           Error.new(
             :compatible_form_not_found,
             :selection,
             "no Form and profile declare the requested operation",
             %{
               affordance_type: interaction.type,
               affordance_name: interaction.name,
               operation: interaction.operation
             }
           )}
      end
    end
  end

  defp find_candidate(forms, profiles, document, affordance, interaction) do
    Enum.find_value(forms, fn form_map ->
      Enum.find_value(profiles, fn profile ->
        match_candidate(document, affordance, form_map, interaction, profile)
      end)
    end)
  end

  defp validate_candidates(forms, profiles) do
    cond do
      not is_list(forms) ->
        {:error, Error.new(:invalid_selection_input, :selection, "selection input is invalid")}

      not Limits.list_within?(profiles, Limits.maximum(:binding_profiles)) ->
        {:error,
         Error.new(
           :profile_limit_exceeded,
           :selection,
           "selection exceeds the binding-profile limit",
           %{max_profiles: Limits.maximum(:binding_profiles)}
         )}

      not Enum.all?(profiles, &match?(%BindingProfile{}, &1)) ->
        {:error, Error.new(:invalid_selection_input, :selection, "selection input is invalid")}

      not Limits.list_within?(forms, Limits.maximum(:forms_per_interaction)) ->
        {:error,
         Error.new(
           :form_limit_exceeded,
           :selection,
           "interaction exceeds the Form scan limit",
           %{max_forms: Limits.maximum(:forms_per_interaction)}
         )}

      true ->
        :ok
    end
  end

  defp match_candidate(
         document,
         affordance,
         form_map,
         interaction,
         %BindingProfile{} = profile
       )
       when is_map(form_map) do
    with true <- BindingProfile.supports_operation?(profile, interaction.operation),
         {:ok, form} <- Form.new(form_map, for: interaction.type),
         true <-
           interaction.operation in Enum.map(
             effective_operations(form, affordance, interaction.type),
             &operation_atom/1
           ),
         {:ok, resolved_href, scheme} <- resolve_href(document, Form.href(form)),
         true <- BindingProfile.supports_scheme?(profile, scheme),
         true <- BindingProfile.supports_media_type?(profile, Map.get(form_map, "contentType")) do
      {form, resolved_href, profile}
    else
      _no_match -> nil
    end
  end

  defp match_candidate(_document, _affordance, _form_map, _interaction, _profile), do: nil

  defp effective_operations(form, affordance, type) do
    Form.operations(form,
      for: type,
      read_only: Map.get(affordance, "readOnly") == true,
      write_only: Map.get(affordance, "writeOnly") == true
    )
  end

  defp operation_atom(name) when is_binary(name) do
    Enum.find(Wotex.Runtime.operations(), :invalid, &(Atom.to_string(&1) == name))
  end

  defp resolve_href(document, href) do
    uri = URI.parse(href)

    cond do
      is_binary(uri.scheme) and uri.scheme != "" ->
        {:ok, href, String.downcase(uri.scheme)}

      is_binary(document["base"]) ->
        resolve_relative(document["base"], href)

      true ->
        :error
    end
  rescue
    URI.Error -> :error
  end

  defp resolve_relative(base, href) do
    base_uri = URI.parse(base)
    merged = URI.merge(base_uri, href)
    resolved = URI.to_string(merged)
    scheme = URI.parse(resolved).scheme

    if is_binary(scheme) and scheme != "" do
      {:ok, resolved, String.downcase(scheme)}
    else
      :error
    end
  rescue
    URI.Error -> :error
  end

  defp security(document, affordance, form) do
    names =
      form
      |> Map.get("security", Map.get(affordance, "security", Map.get(document, "security", [])))
      |> List.wrap()

    definitions = Map.get(document, "securityDefinitions", %{})

    %{
      names: names,
      definitions: Map.take(definitions, names)
    }
  end
end
