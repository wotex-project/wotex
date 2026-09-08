defmodule Wotex.Nx.WindowSelectionPropertyTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Wotex.Nx.{Error, TestFactory, Window}

  test "selection-work admission uses the documented score including empty and singleton inputs" do
    all_observations =
      for n <- 1..9, do: TestFactory.observation(id: "observation-#{n}", observed_at: n)

    features = [
      TestFactory.feature(),
      TestFactory.feature(name: "humidity", affordance_name: "humidity")
    ]

    for {n, log_factor} <- [{0, 1}, {1, 1}, {2, 1}, {3, 2}, {4, 2}, {5, 3}, {7, 3}, {8, 3}, {9, 4}],
        count <- [2, 3],
        feature_count <- [1, 2],
        strategy <- [:exact, :latest, :nearest] do
      observations = Enum.take(all_observations, n)
      schema = TestFactory.schema(Enum.take(features, feature_count))
      {:ok, window} = Window.new(start: 0, step: 2, count: count, strategy: strategy)
      work = n + count * feature_count * log_factor

      assert {:ok, rows} = Window.resample(observations, schema, window, max_work: work)
      assert length(rows) == count
      assert {:ok, ^rows} = Window.resample(Enum.reverse(observations), schema, window)

      assert {:error, %Error{code: :window_work_limit_exceeded, details: details}} =
               Window.resample(observations, schema, window, max_work: work - 1)

      assert details == %{work: work, max_work: work - 1}
    end
  end

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

  property "nearest selection agrees with an exhaustive reference for every row" do
    check all(
            times <- list_of(integer(-20..20), max_length: 60),
            age <- member_of([nil, 0, 3, 40])
          ) do
      observations =
        times
        |> Enum.with_index()
        |> Enum.map(fn {time, id} ->
          TestFactory.observation(id: "observation-#{id}", observed_at: time)
        end)

      schema = TestFactory.schema()

      {:ok, window} =
        Window.new(start: -25, step: 5, count: 11, strategy: :nearest, max_age: age)

      assert {:ok, rows} = Window.resample(observations, schema, window)
      assert {:ok, ^rows} = Window.resample(Enum.reverse(observations), schema, window)

      Enum.each(rows, fn row ->
        selected =
          observations
          |> Enum.sort_by(&{abs(&1.observed_at - row.timestamp), &1.observed_at, &1.id})
          |> List.first()

        expected =
          if selected && (is_nil(age) || abs(row.timestamp - selected.observed_at) <= age),
            do: selected,
            else: nil

        assert row.observations["temperature"] == expected
      end)
    end
  end
end
