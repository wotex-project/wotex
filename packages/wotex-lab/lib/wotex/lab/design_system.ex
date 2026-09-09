defmodule Wotex.Lab.DesignSystem do
  @moduledoc """
  Neutral, framework-independent design tokens for the reference workbench.

  The returned stylesheet is scoped to `.wotex-lab`. A host serves it as a
  local asset and applies that class to its root container. Set `data-theme`
  to `light` or `dark` to override system preference. Consumers may override
  semantic CSS variables; this module starts no UI or asset pipeline.

  `tokens/0` returns inert, string-keyed data for hosts that render controls
  themselves. `stylesheet/0` produces deterministic CSS from the same contract,
  keeping color, typography, spacing, focus, and status semantics aligned across
  the optional workbench frontends.
  """

  @version "0.1.0"
  @tokens %{
    "base" => %{
      "font-sans" => "system-ui, -apple-system, BlinkMacSystemFont, sans-serif",
      "font-mono" => "ui-monospace, SFMono-Regular, Consolas, monospace",
      "text-sm" => "0.875rem",
      "text-base" => "1rem",
      "text-title" => "1.5rem",
      "line-height" => "1.5",
      "space-1" => "0.25rem",
      "space-2" => "0.5rem",
      "space-3" => "0.75rem",
      "space-4" => "1rem",
      "space-6" => "1.5rem",
      "space-8" => "2rem",
      "radius-control" => "0.5rem",
      "radius-panel" => "0.75rem",
      "sidebar-width" => "15rem",
      "reading-width" => "48rem",
      "control-height" => "2.75rem"
    },
    "light" => %{
      "color-bg" => "#ffffff",
      "color-panel" => "#f5f5f5",
      "color-text" => "#202020",
      "color-muted" => "#595959",
      "color-border" => "#767676",
      "color-focus" => "#1d4ed8",
      "color-accent" => "#294f77",
      "color-on-accent" => "#ffffff",
      "color-success" => "#17633b",
      "color-warning" => "#815000",
      "color-danger" => "#b42318"
    },
    "dark" => %{
      "color-bg" => "#212121",
      "color-panel" => "#2b2b2b",
      "color-text" => "#f2f2f2",
      "color-muted" => "#b9b9b9",
      "color-border" => "#939393",
      "color-focus" => "#a5c8ff",
      "color-accent" => "#b1cce8",
      "color-on-accent" => "#182533",
      "color-success" => "#8cd7ab",
      "color-warning" => "#eac37b",
      "color-danger" => "#ffb4aa"
    }
  }

  @typedoc "A named group of CSS tokens with string keys and CSS-value strings."
  @type tokens :: %{String.t() => %{String.t() => String.t()}}

  @doc "Returns the version of the shared token contract."
  @spec version() :: String.t()
  def version, do: @version

  @doc "Returns base, light and dark tokens as machine-readable inert data."
  @spec tokens() :: tokens()
  def tokens, do: @tokens

  @doc "Returns deterministic, scoped CSS with system-theme and explicit-theme support."
  @spec stylesheet() :: String.t()
  def stylesheet do
    """
    .wotex-lab {
    #{declarations(Map.merge(@tokens["base"], @tokens["light"]))}
      color-scheme: light;
      color: var(--wl-color-text);
      background: var(--wl-color-bg);
      font-family: var(--wl-font-sans);
      font-size: var(--wl-text-base);
      line-height: var(--wl-line-height);
    }
    .wotex-lab[data-theme="dark"] {
    #{declarations(@tokens["dark"])}
      color-scheme: dark;
    }
    @media (prefers-color-scheme: dark) {
      .wotex-lab:not([data-theme]) {
    #{declarations(@tokens["dark"])}
        color-scheme: dark;
      }
    }
    .wotex-lab :focus-visible {
      outline: 2px solid var(--wl-color-focus);
      outline-offset: 3px;
    }
    """
  end

  defp declarations(tokens) do
    tokens
    |> Enum.sort()
    |> Enum.map_join("\n", fn {name, value} -> "  --wl-#{name}: #{value};" end)
  end
end
