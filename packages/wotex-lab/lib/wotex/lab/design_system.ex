defmodule Wotex.Lab.DesignSystem do
  @moduledoc """
  Owns the visual contract used by the Wotex Lab reference hosts.

  The contract contains Wotex semantic tokens, the three admitted Svelte
  island descriptors, deterministic fixture identities and scoped CSS. It has
  no Phoenix or browser dependency, reads no files, starts no process and
  performs no network operation.
  """

  alias Wotex.Lab.Island.Component

  @version "0.4.0"
  @shared %{
    "semantic.space.controlX" => "0.75rem",
    "semantic.space.controlY" => "0.5rem",
    "semantic.space.panel" => "1rem",
    "semantic.space.section" => "2rem",
    "semantic.radius.control" => "0.625rem",
    "semantic.radius.panel" => "0.875rem",
    "semantic.motion.interaction" => "120ms",
    "semantic.motion.panel" => "180ms"
  }
  @light %{
    "semantic.color.canvas" => "#f4f2ee",
    "semantic.color.surface" => "#fbfaf7",
    "semantic.color.text" => "#263044",
    "semantic.color.muted" => "#5c6370",
    "semantic.color.border" => "#737984",
    "semantic.color.accent" => "#294f77",
    "semantic.color.accentText" => "#ffffff",
    "semantic.color.focus" => "#1d4f91",
    "semantic.color.danger" => "#b42318",
    "semantic.color.warning" => "#815000",
    "semantic.color.success" => "#17633b"
  }
  @dark %{
    "semantic.color.canvas" => "#142b50",
    "semantic.color.surface" => "#1b3864",
    "semantic.color.text" => "#e0f4ff",
    "semantic.color.muted" => "#acc8da",
    "semantic.color.border" => "#879db5",
    "semantic.color.accent" => "#e0f4ff",
    "semantic.color.accentText" => "#142b50",
    "semantic.color.focus" => "#a8d8ff",
    "semantic.color.danger" => "#ffb4aa",
    "semantic.color.warning" => "#f4ca82",
    "semantic.color.success" => "#8cd7ab"
  }
  @contrast %{
    "semantic.color.canvas" => "#000000",
    "semantic.color.surface" => "#000000",
    "semantic.color.text" => "#ffffff",
    "semantic.color.muted" => "#ffffff",
    "semantic.color.border" => "#ffffff",
    "semantic.color.accent" => "#ffff00",
    "semantic.color.accentText" => "#000000",
    "semantic.color.focus" => "#ffff00",
    "semantic.color.danger" => "#ff6060",
    "semantic.color.warning" => "#ffff00",
    "semantic.color.success" => "#00ff90"
  }
  @tokens %{
    "system" => Map.merge(@shared, @light),
    "light" => Map.merge(@shared, @light),
    "dark" => Map.merge(@shared, @dark),
    "contrast" => Map.merge(@shared, @contrast)
  }

  @typedoc "A reader theme mapped to closed Wotex semantic roles."
  @type tokens :: %{String.t() => %{String.t() => String.t()}}

  @doc "Returns the version of the Wotex Lab design contract."
  @spec version() :: String.t()
  def version, do: @version

  @doc "Returns system, light, dark and high-contrast semantic tokens."
  @spec tokens() :: tokens()
  def tokens, do: @tokens

  @doc "Returns the identities shared by Workbench, documentation and Storybook."
  @spec contract() :: map()
  def contract do
    %{
      "schema_version" => "wotex-lab-design-system/v1",
      "version" => @version,
      "token_digest" => digest(@tokens),
      "component_registry_digest" => Component.digest(),
      "story_fixture_digest" => fixture_digest(),
      "stylesheet_digest" => digest(stylesheet())
    }
  end

  @doc "Validates and normalizes a closed map of Wotex semantic token overrides."
  @spec validate_overrides(map() | keyword()) :: {:ok, map()} | {:error, term()}
  def validate_overrides(overrides) when is_list(overrides) do
    if Keyword.keyword?(overrides),
      do: validate_overrides(Map.new(overrides)),
      else: {:error, {:invalid_design_token_overrides, overrides}}
  end

  def validate_overrides(overrides) when is_map(overrides) do
    roles = @tokens["system"]

    Enum.reduce_while(overrides, {:ok, %{}}, fn {role, value}, {:ok, valid} ->
      role = to_string(role)

      if Map.has_key?(roles, role) and valid_value?(role, value),
        do: {:cont, {:ok, Map.put(valid, role, value)}},
        else: {:halt, {:error, {:invalid_design_token_override, role}}}
    end)
  end

  def validate_overrides(overrides), do: {:error, {:invalid_design_token_overrides, overrides}}

  @doc "Builds deterministic CSS declarations for validated token overrides."
  @spec override_style(map() | keyword()) :: {:ok, String.t()} | {:error, term()}
  def override_style(overrides) do
    with {:ok, overrides} <- validate_overrides(overrides) do
      {:ok,
       overrides
       |> Enum.sort()
       |> Enum.map_join("", fn {role, value} -> "#{variable(role)}:#{value};" end)}
    end
  end

  @doc "Returns deterministic CSS scoped to Wotex Lab surfaces."
  @spec stylesheet() :: String.t()
  def stylesheet do
    """
    .wotex-lab[data-wotex-design-system],
    .wotex-lab[data-wotex-design-system] [data-wotex-design-system] {
    #{declarations(@tokens["system"])}
    #{aliases()}
      --wl-font-sans: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      --wl-font-mono: ui-monospace, SFMono-Regular, Consolas, monospace;
      --wl-text-sm: 0.875rem;
      --wl-text-base: 1rem;
      --wl-text-title: 1.75rem;
      --wl-line-height: 1.5;
      --wl-space-1: 0.25rem;
      --wl-space-2: 0.5rem;
      --wl-space-3: 0.75rem;
      --wl-space-4: 1rem;
      --wl-space-6: 1.5rem;
      --wl-space-8: 2rem;
      --wl-sidebar-width: 14.5rem;
      --wl-reading-width: 48rem;
      --wl-control-height: 2.75rem;
      color-scheme: light;
      color: var(--wotex-semantic-color-text);
      background: var(--wotex-semantic-color-canvas);
      font-family: var(--wl-font-sans);
      font-size: var(--wl-text-base);
      line-height: var(--wl-line-height);
    }
    .wotex-lab[data-wotex-design-system][data-wotex-theme="light"],
    .wotex-lab[data-wotex-design-system][data-wotex-theme="light"] [data-wotex-design-system] {
    #{declarations(@tokens["light"])}
      color-scheme: light;
    }
    .wotex-lab[data-wotex-design-system][data-wotex-theme="dark"],
    .wotex-lab[data-wotex-design-system][data-wotex-theme="dark"] [data-wotex-design-system] {
    #{declarations(@tokens["dark"])}
      color-scheme: dark;
    }
    .wotex-lab[data-wotex-design-system][data-wotex-theme="contrast"],
    .wotex-lab[data-wotex-design-system][data-wotex-theme="contrast"] [data-wotex-design-system] {
    #{declarations(@tokens["contrast"])}
      color-scheme: dark;
    }
    @media (prefers-color-scheme: dark) {
      .wotex-lab[data-wotex-design-system]:not([data-wotex-theme="light"]):not([data-wotex-theme="dark"]):not([data-wotex-theme="contrast"]),
      .wotex-lab[data-wotex-design-system]:not([data-wotex-theme="light"]):not([data-wotex-theme="dark"]):not([data-wotex-theme="contrast"]) [data-wotex-design-system] {
    #{declarations(@tokens["dark"])}
        color-scheme: dark;
      }
    }
    .wotex-lab[data-wotex-design-system] :focus-visible {
      outline: 2px solid var(--wotex-semantic-color-focus);
      outline-offset: 3px;
    }
    """
  end

  defp fixture_digest do
    Component.all()
    |> Enum.map(fn descriptor ->
      %{
        "schema" => "wotex-lab-story/v1",
        "id" => descriptor["story_id"],
        "component" => descriptor["id"],
        "states" => descriptor["states"],
        "fallback" => descriptor["fallback"]
      }
    end)
    |> digest()
  end

  defp digest(value) when is_binary(value),
    do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, value), case: :lower)

  defp digest(value) do
    {:ok, bytes} = Wotex.JSON.encode(value)
    digest(bytes)
  end

  defp declarations(tokens) do
    tokens
    |> Enum.sort()
    |> Enum.map_join("\n", fn {name, value} -> "  #{variable(name)}: #{value};" end)
  end

  defp variable(role) do
    name =
      role
      |> String.replace(".", "-")
      |> String.replace(~r/([A-Z])/, "-\\1")
      |> String.downcase()

    "--wotex-" <> name
  end

  defp aliases do
    """
      --wl-color-bg: var(--wotex-semantic-color-canvas);
      --wl-color-panel: var(--wotex-semantic-color-surface);
      --wl-color-text: var(--wotex-semantic-color-text);
      --wl-color-muted: var(--wotex-semantic-color-muted);
      --wl-color-border: var(--wotex-semantic-color-border);
      --wl-color-focus: var(--wotex-semantic-color-focus);
      --wl-color-accent: var(--wotex-semantic-color-accent);
      --wl-color-on-accent: var(--wotex-semantic-color-accent-text);
      --wl-color-success: var(--wotex-semantic-color-success);
      --wl-color-warning: var(--wotex-semantic-color-warning);
      --wl-color-danger: var(--wotex-semantic-color-danger);
      --wl-radius-control: var(--wotex-semantic-radius-control);
      --wl-radius-panel: var(--wotex-semantic-radius-panel);
    """
    |> String.trim_trailing()
  end

  defp valid_value?("semantic.color." <> _, value),
    do:
      is_binary(value) and
        Regex.match?(~r/\A(?:#[0-9a-fA-F]{6,8}|(?:rgb|hsl|oklch)\([^;{}]+\))\z/, value)

  defp valid_value?("semantic.space." <> _, value), do: dimension?(value)
  defp valid_value?("semantic.radius." <> _, value), do: dimension?(value)

  defp valid_value?("semantic.motion." <> _, value),
    do: is_binary(value) and Regex.match?(~r/\A(?:\d+|\d*\.\d+)(?:ms|s)\z/, value)

  defp valid_value?(_, _), do: false

  defp dimension?(value),
    do: is_binary(value) and Regex.match?(~r/\A-?(?:\d+|\d*\.\d+)(?:px|rem|em|ch|%)\z/, value)
end
