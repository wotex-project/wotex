defmodule Wotex.Nx.WindowSelectionPropertyTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Wotex.Nx.{TestFactory, Window}

  property "latest and exact selection agree with a sorted reference for every row" do
    check all(
            times <- list_of(integer(-20..20), max_length: 60),
            age <- member_of([nil, 0, 5, 40])
          ) do
      observations =
        times
        |> Enum.with_index()
        |> Enum.map(fn {time, id} ->
          TestFactory.observation(id: "observation-#{id}", observed_at: time)
        end)

      schema = TestFactory.schema()

      for strategy <- [:latest, :exact] do
        {:ok, window} = Window.new(start: -25, step: 5, count: 11, strategy: strategy, max_age: age)
        assert {:ok, rows} = Window.resample(observations, schema, window)
        assert {:ok, ^rows} = Window.resample(Enum.reverse(observations), schema, window)

        Enum.each(rows, fn row ->
          selected =
            observations
            |> Enum.filter(fn observation ->
              if strategy == :exact,
                do: observation.observed_at == row.timestamp,
                else: observation.observed_at <= row.timestamp
            end)
            |> Enum.sort_by(&{-&1.observed_at, &1.id})
            |> List.first()

          expected =
            if selected && (is_nil(age) || abs(row.timestamp - selected.observed_at) <= age),
              do: selected

          assert row.observations["temperature"] == expected
        end)
      end
    end
  end
end
