defmodule WotexLabWorkbenchWeb.Components.Field do
  @moduledoc """
  Renders labelled text, number, select and textarea controls.

  The supplied id links the label, help and error text to the control through
  standard HTML and ARIA attributes. Select options retain caller order and
  compare their string representations with the selected value. Browser
  constraints such as `maxlength` and `required` aid input; the receiving
  server still validates submitted values and owns error classification.
  """

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
    describedby =
      [assigns.help && "#{assigns.id}-help", assigns.error && "#{assigns.id}-error"]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    assigns = assign(assigns, :describedby, if(describedby != "", do: describedby))

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
