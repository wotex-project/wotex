defmodule WotexLabWorkbenchWeb.Components.Field do
  @moduledoc "Labelled form controls with help and error text linked through `aria-describedby`."

  use Phoenix.Component

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text", values: ~w(text number select textarea)
  attr :value, :any, default: nil
  attr :options, :list, default: [], doc: "`{label, value}` pairs for a select"
  attr :help, :string, default: nil
  attr :error, :string, default: nil
  attr :rest, :global, include: ~w(min max step rows maxlength disabled required placeholder)

  @doc "Renders a labelled control."
  @spec field(map()) :: Phoenix.LiveView.Rendered.t()
  def field(assigns) do
    assigns =
      assign(
        assigns,
        :describedby,
        [assigns.help && "#{assigns.id}-help", assigns.error && "#{assigns.id}-error"]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")
        |> case do
          "" -> nil
          ids -> ids
        end
      )

    ~H"""
    <div class={["wl-field", @error && "wl-field-invalid"]}>
      <label for={@id}>{@label}</label>
      <%= case @type do %>
        <% "select" -> %>
          <select
            id={@id}
            name={@name}
            aria-describedby={@describedby}
            aria-invalid={@error && "true"}
            {@rest}
          >
            <option
              :for={{label, value} <- @options}
              value={value}
              selected={to_string(value) == to_string(@value)}
            >
              {label}
            </option>
          </select>
        <% "textarea" -> %>
          <textarea
            id={@id}
            name={@name}
            aria-describedby={@describedby}
            aria-invalid={@error && "true"}
            {@rest}
          >{@value}</textarea>
        <% type -> %>
          <input
            id={@id}
            name={@name}
            type={type}
            value={@value}
            aria-describedby={@describedby}
            aria-invalid={@error && "true"}
            {@rest}
          />
      <% end %>
      <p :if={@help} id={"#{@id}-help"} class="wl-help">{@help}</p>
      <p :if={@error} id={"#{@id}-error"} class="wl-error" role="alert">{@error}</p>
    </div>
    """
  end
end
