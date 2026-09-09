defmodule Wotex.Lab.DesignSystemTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.DesignSystem

  test "tokens are versioned JSON-compatible data and both themes have the same roles" do
    assert DesignSystem.version() == "0.1.0"
    tokens = DesignSystem.tokens()
    assert Enum.sort(Map.keys(tokens)) == ["base", "dark", "light"]
    assert Enum.sort(Map.keys(tokens["light"])) == Enum.sort(Map.keys(tokens["dark"]))
    assert {:ok, schema} = Wotex.DataSchema.new(%{"x-example:design-tokens" => tokens})
    assert Wotex.DataSchema.to_map(schema)["x-example:design-tokens"] == tokens
  end

  test "CSS is deterministic, scoped and derived from the tokens without external assets" do
    css = DesignSystem.stylesheet()
    assert css == DesignSystem.stylesheet()
    assert css =~ ".wotex-lab[data-theme=\"dark\"]"
    assert css =~ ".wotex-lab:not([data-theme])"
    assert css =~ ":focus-visible"
    refute css =~ ":root"
    refute css =~ "@import"
    refute css =~ "url("

    for {_, tokens} <- DesignSystem.tokens(), {name, value} <- tokens do
      assert css =~ "--wl-#{name}: #{value};"
    end
  end

  test "text and state colors meet normal-text contrast on both neutral surfaces" do
    for theme <- ["light", "dark"], surface <- ["color-bg", "color-panel"] do
      tokens = DesignSystem.tokens()[theme]

      for foreground <- ~w(color-text color-muted color-success color-warning color-danger) do
        assert contrast(tokens[foreground], tokens[surface]) >= 4.5
      end

      assert contrast(tokens["color-focus"], tokens[surface]) >= 3.0
      assert contrast(tokens["color-border"], tokens[surface]) >= 3.0
      assert contrast(tokens["color-on-accent"], tokens["color-accent"]) >= 4.5
    end
  end

  defp contrast(left, right) do
    [low, high] = Enum.sort([luminance(left), luminance(right)])
    (high + 0.05) / (low + 0.05)
  end

  defp luminance("#" <> hex) do
    <<red, green, blue>> = Base.decode16!(hex, case: :mixed)
    0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  end

  defp linear(channel) do
    value = channel / 255
    if value <= 0.04045, do: value / 12.92, else: :math.pow((value + 0.055) / 1.055, 2.4)
  end
end
