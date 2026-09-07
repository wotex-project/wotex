defmodule Wotex.Directory.RegistrationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Directory.{Error, Registration}

  @now ~U[2026-09-02 10:00:00Z]

  test "assigns server times and gives ttl precedence over absolute expiry" do
    input =
      {:present,
       %{
         "ttl" => 60,
         "expires" => "2030-01-01T00:00:00+02:00",
         "x-example:source" => "registration"
       }}

    assert {:ok, registration} = Registration.create(@now, input, :register)
    assert registration.created == @now
    assert registration.modified == @now
    assert registration.ttl == 60
    assert registration.expires == ~U[2026-09-02 10:01:00Z]
    assert registration.extensions == %{"x-example:source" => "registration"}

    assert Registration.to_map(registration) == %{
             "created" => "2026-09-02T10:00:00Z",
             "modified" => "2026-09-02T10:00:00Z",
             "expires" => "2026-09-02T10:01:00Z",
             "ttl" => 60,
             "x-example:source" => "registration"
           }
  end

  test "accepts RFC 3339 offsets and normalizes absolute time" do
    assert {:ok, registration} =
             Registration.create(
               @now,
               {:present, %{"expires" => "2026-09-02T13:00:00+02:00"}},
               :register
             )

    assert registration.expires == ~U[2026-09-02 11:00:00Z]
  end

  test "rejects client assignment to server fields and invalid ttl" do
    for field <- ~w(created modified retrieved) do
      path = "/registration/" <> field

      assert {:error, %Error{code: :invalid_request, path: ^path}} =
               Registration.create(@now, {:present, %{field => "value"}}, :register)
    end

    assert {:error, %Error{code: :invalid_request, path: "/registration/ttl"}} =
             Registration.create(@now, {:present, %{"ttl" => -1}}, :register)

    assert {:error, %Error{code: :invalid_request}} =
             Registration.create(@now, {:present, %{"ttl" => 4_294_967_296}}, :register)
  end

  test "refresh preserves creation and recalculates relative expiry" do
    assert {:ok, initial} =
             Registration.create(@now, {:present, %{"ttl" => 60}}, :register)

    later = DateTime.add(@now, 30, :second)
    assert {:ok, refreshed} = Registration.refresh(initial, later, :absent, :replace)
    assert refreshed.created == @now
    assert refreshed.modified == later
    assert refreshed.expires == DateTime.add(later, 60, :second)
  end

  test "reports clock regression deterministically" do
    assert {:ok, initial} = Registration.create(@now, :absent, :register)
    later = DateTime.add(@now, 60, :second)
    assert {:ok, refreshed} = Registration.refresh(initial, later, :absent, :replace)

    earlier = DateTime.add(later, -1, :second)

    assert {:error,
            %Error{code: :clock_regression, phase: :clock, details: %{operation: :replace}}} =
             Registration.refresh(refreshed, earlier, :absent, :replace)
  end

  test "retrieved is return-only and expiry is inclusive" do
    assert {:ok, registration} =
             Registration.create(@now, {:present, %{"ttl" => 0}}, :register)

    assert Registration.expired?(registration, @now)

    retrieved = Registration.mark_retrieved(registration, @now)
    assert retrieved.retrieved == @now
    assert Registration.for_storage(retrieved).retrieved == nil
  end
end
