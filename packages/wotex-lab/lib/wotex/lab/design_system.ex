defmodule Wotex.Lab.DesignSystem do
  @moduledoc """
  Wotex theme overrides for the shared Phoenix Assets design system.

  The token map contains only PHA.02 semantic roles. Hosts validate a selected
  theme through `PhoenixAssets.DesignSystem.validate_overrides/1` before adding
  it to a page. `stylesheet/0` emits the same values as scoped CSS and retains
  the established `--wl-*` aliases used by Wotex-specific compositions.

  The module has no Phoenix or browser dependency. It reads no files, starts no
  process and performs no network operation.
  """

  @version "0.2.0"
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
    "semantic.color.canvas" => "#ffffff",
    "semantic.color.surface" => "#f5f5f5",
    "semantic.color.text" => "#202020",
    "semantic.color.muted" => "#595959",
    "semantic.color.border" => "#767676",
    "semantic.color.accent" => "#294f77",
    "semantic.color.accentText" => "#ffffff",
    "semantic.color.focus" => "#1d4ed8",
    "semantic.color.danger" => "#b42318",
    "semantic.color.warning" => "#815000",
    "semantic.color.success" => "#17633b"
  }
  @dark %{
    "semantic.color.canvas" => "#212121",
    "semantic.color.surface" => "#2b2b2b",
    "semantic.color.text" => "#f2f2f2",
    "semantic.color.muted" => "#b9b9b9",
    "semantic.color.border" => "#939393",
    "semantic.color.accent" => "#b1cce8",
    "semantic.color.accentText" => "#182533",
    "semantic.color.focus" => "#a5c8ff",
    "semantic.color.danger" => "#ffb4aa",
    "semantic.color.warning" => "#eac37b",
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

  @typedoc "A reader theme mapped to closed PHA.02 semantic roles."
  @type tokens :: %{String.t() => %{String.t() => String.t()}}

  @doc "Returns the version of the Wotex theme contract."
  @spec version() :: String.t()
  def version, do: @version

  @doc "Returns system, light, dark and high-contrast semantic overrides."
  @spec tokens() :: tokens()
  def tokens, do: @tokens

  @doc "Returns deterministic scoped CSS for the shared and Wotex-specific surfaces."
  @spec stylesheet() :: String.t()
  def stylesheet do
    """
    .wotex-lab[data-pa-design-system] {
    #{declarations(@tokens["system"])}
    #{aliases()}
      --wl-font-sans: system-ui, -apple-system, BlinkMacSystemFont, sans-serif;
      --wl-font-mono: ui-monospace, SFMono-Regular, Consolas, monospace;
      --wl-text-sm: 0.875rem;
      --wl-text-base: 1rem;
      --wl-text-title: 1.5rem;
      --wl-line-height: 1.5;
      --wl-space-1: 0.25rem;
      --wl-space-2: 0.5rem;
      --wl-space-3: 0.75rem;
      --wl-space-4: 1rem;
      --wl-space-6: 1.5rem;
      --wl-space-8: 2rem;
      --wl-sidebar-width: 15rem;
      --wl-reading-width: 48rem;
      --wl-control-height: 2.75rem;
      color-scheme: light;
      color: var(--pa-semantic-color-text);
      background: var(--pa-semantic-color-canvas);
      font-family: var(--wl-font-sans);
      font-size: var(--wl-text-base);
      line-height: var(--wl-line-height);
    }
    .wotex-lab[data-pa-design-system][data-pa-theme="light"] {
    #{declarations(@tokens["light"])}
      color-scheme: light;
    }
    .wotex-lab[data-pa-design-system][data-pa-theme="dark"] {
    #{declarations(@tokens["dark"])}
      color-scheme: dark;
    }
    .wotex-lab[data-pa-design-system][data-pa-theme="contrast"] {
    #{declarations(@tokens["contrast"])}
      color-scheme: dark;
    }
    @media (prefers-color-scheme: dark) {
      .wotex-lab[data-pa-design-system]:not([data-pa-theme="light"]):not([data-pa-theme="dark"]):not([data-pa-theme="contrast"]) {
    #{declarations(@tokens["dark"])}
        color-scheme: dark;
      }
    }
    .wotex-lab[data-pa-design-system] :focus-visible {
      outline: 2px solid var(--pa-semantic-color-focus);
      outline-offset: 3px;
    }
    """
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

    "--pa-" <> name
  end

  defp aliases do
    """
      --wl-color-bg: var(--pa-semantic-color-canvas);
      --wl-color-panel: var(--pa-semantic-color-surface);
      --wl-color-text: var(--pa-semantic-color-text);
      --wl-color-muted: var(--pa-semantic-color-muted);
      --wl-color-border: var(--pa-semantic-color-border);
      --wl-color-focus: var(--pa-semantic-color-focus);
      --wl-color-accent: var(--pa-semantic-color-accent);
      --wl-color-on-accent: var(--pa-semantic-color-accent-text);
      --wl-color-success: var(--pa-semantic-color-success);
      --wl-color-warning: var(--pa-semantic-color-warning);
      --wl-color-danger: var(--pa-semantic-color-danger);
      --wl-radius-control: var(--pa-semantic-radius-control);
      --wl-radius-panel: var(--pa-semantic-radius-panel);
    """
    |> String.trim_trailing()
  end
end
