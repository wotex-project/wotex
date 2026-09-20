defmodule Wotex.Lab.DesignSystemTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.DesignSystem

  test "tokens are versioned JSON-compatible data and every theme has the same roles" do
    assert DesignSystem.version() == "0.2.0"
    tokens = DesignSystem.tokens()
    assert Enum.sort(Map.keys(tokens)) == ["contrast", "dark", "light", "system"]

    roles = for theme <- Map.values(tokens), do: Enum.sort(Map.keys(theme))
    assert length(Enum.uniq(roles)) == 1
    assert Enum.all?(hd(roles), &String.starts_with?(&1, "semantic."))
    assert {:ok, schema} = Wotex.DataSchema.new(%{"x-example:design-tokens" => tokens})
    assert Wotex.DataSchema.to_map(schema)["x-example:design-tokens"] == tokens
  end

  test "CSS is deterministic, scoped and derived from the tokens without external assets" do
    css = DesignSystem.stylesheet()
    assert css == DesignSystem.stylesheet()
    assert css =~ ".wotex-lab[data-pa-design-system][data-pa-theme=\"dark\"]"
    assert css =~ ".wotex-lab[data-pa-design-system][data-pa-theme=\"contrast\"]"
    assert css =~ ":focus-visible"
    refute css =~ ":root"
    refute css =~ "@import"
    refute css =~ "url("

    for {_, tokens} <- DesignSystem.tokens(), {name, value} <- tokens do
      variable =
        name
        |> String.replace(".", "-")
        |> String.replace(~r/([A-Z])/, "-\\1")
        |> String.downcase()

      assert css =~ "--pa-#{variable}: #{value};"
    end
  end

  test "text and state colors meet normal-text contrast on both neutral surfaces" do
    for theme <- ["light", "dark", "contrast"],
        surface <- ["semantic.color.canvas", "semantic.color.surface"] do
      tokens = DesignSystem.tokens()[theme]

      for foreground <-
            ~w(semantic.color.text semantic.color.muted semantic.color.success semantic.color.warning semantic.color.danger) do
        assert contrast(tokens[foreground], tokens[surface]) >= 4.5
      end

      assert contrast(tokens["semantic.color.focus"], tokens[surface]) >= 3.0
      assert contrast(tokens["semantic.color.border"], tokens[surface]) >= 3.0

      assert contrast(tokens["semantic.color.accentText"], tokens["semantic.color.accent"]) >=
               4.5
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
