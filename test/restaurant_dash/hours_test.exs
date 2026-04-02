defmodule RestaurantDash.HoursTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Hours
  alias RestaurantDash.Hours.{OperatingHour, Closure}
  alias RestaurantDash.Tenancy

  defp restaurant_fixture do
    slug = "hours-test-#{System.unique_integer([:positive])}"

    {:ok, r} =
      Tenancy.create_restaurant(%{name: "Hours Test", slug: slug, timezone: "America/Chicago"})

    r
  end

  describe "upsert_hours/1" do
    test "creates hours for a day" do
      restaurant = restaurant_fixture()

      assert {:ok, %OperatingHour{} = h} =
               Hours.upsert_hours(%{
                 restaurant_id: restaurant.id,
                 day_of_week: 1,
                 open_time: ~T[09:00:00],
                 close_time: ~T[21:00:00]
               })

      assert h.day_of_week == 1
      assert h.open_time == ~T[09:00:00]
      assert h.close_time == ~T[21:00:00]
    end

    test "updates existing hours" do
      restaurant = restaurant_fixture()

      {:ok, _} =
        Hours.upsert_hours(%{
          restaurant_id: restaurant.id,
          day_of_week: 2,
          open_time: ~T[09:00:00],
          close_time: ~T[17:00:00]
        })

      assert {:ok, updated} =
               Hours.upsert_hours(%{
                 restaurant_id: restaurant.id,
                 day_of_week: 2,
                 open_time: ~T[10:00:00],
                 close_time: ~T[22:00:00]
               })

      assert updated.open_time == ~T[10:00:00]
    end

    test "rejects invalid day_of_week" do
      restaurant = restaurant_fixture()

      assert {:error, changeset} =
               Hours.upsert_hours(%{
                 restaurant_id: restaurant.id,
                 day_of_week: 7,
                 open_time: ~T[09:00:00],
                 close_time: ~T[17:00:00]
               })

      assert "is invalid" in errors_on(changeset).day_of_week
    end

    test "rejects close_time before open_time" do
      restaurant = restaurant_fixture()

      assert {:error, changeset} =
               Hours.upsert_hours(%{
                 restaurant_id: restaurant.id,
                 day_of_week: 3,
                 open_time: ~T[17:00:00],
                 close_time: ~T[09:00:00]
               })

      assert errors_on(changeset).close_time != []
    end

    test "allows marking a day as closed" do
      restaurant = restaurant_fixture()

      assert {:ok, h} =
               Hours.upsert_hours(%{
                 restaurant_id: restaurant.id,
                 day_of_week: 0,
                 open_time: ~T[00:00:00],
                 close_time: ~T[23:59:00],
                 is_closed: true
               })

      assert h.is_closed == true
    end
  end

  describe "list_hours/1" do
    test "returns hours ordered by day" do
      restaurant = restaurant_fixture()

      Hours.upsert_hours(%{
        restaurant_id: restaurant.id,
        day_of_week: 3,
        open_time: ~T[09:00:00],
        close_time: ~T[17:00:00]
      })

      Hours.upsert_hours(%{
        restaurant_id: restaurant.id,
        day_of_week: 1,
        open_time: ~T[09:00:00],
        close_time: ~T[17:00:00]
      })

      hours = Hours.list_hours(restaurant.id)
      days = Enum.map(hours, & &1.day_of_week)
      assert days == Enum.sort(days)
    end
  end

  describe "closures" do
    test "create_closure/1 creates a holiday closure" do
      restaurant = restaurant_fixture()

      assert {:ok, %Closure{} = c} =
               Hours.create_closure(%{
                 restaurant_id: restaurant.id,
                 date: ~D[2026-12-25],
                 reason: "Christmas"
               })

      assert c.date == ~D[2026-12-25]
      assert c.reason == "Christmas"
    end

    test "list_upcoming_closures/1 returns future closures" do
      restaurant = restaurant_fixture()
      far_future = Date.add(Date.utc_today(), 30)
      past_date = Date.add(Date.utc_today(), -5)

      Hours.create_closure(%{restaurant_id: restaurant.id, date: far_future, reason: "Future"})
      Hours.create_closure(%{restaurant_id: restaurant.id, date: past_date, reason: "Past"})

      upcoming = Hours.list_upcoming_closures(restaurant.id)
      assert Enum.any?(upcoming, &(&1.reason == "Future"))
      refute Enum.any?(upcoming, &(&1.reason == "Past"))
    end
  end

  describe "is_open?/2" do
    test "returns open when within hours" do
      restaurant = restaurant_fixture()
      # Get today's day_of_week in local time
      now = DateTime.utc_now() |> DateTime.shift_zone!("America/Chicago")
      dow = Date.day_of_week(DateTime.to_date(now), :sunday) - 1

      Hours.upsert_hours(%{
        restaurant_id: restaurant.id,
        day_of_week: dow,
        open_time: ~T[00:00:00],
        close_time: ~T[23:59:00],
        is_closed: false
      })

      assert {:open} = Hours.is_open?(restaurant.id, "America/Chicago")
    end

    test "returns closed when marked closed for day" do
      restaurant = restaurant_fixture()
      now = DateTime.utc_now() |> DateTime.shift_zone!("America/Chicago")
      dow = Date.day_of_week(DateTime.to_date(now), :sunday) - 1

      Hours.upsert_hours(%{
        restaurant_id: restaurant.id,
        day_of_week: dow,
        open_time: ~T[09:00:00],
        close_time: ~T[17:00:00],
        is_closed: true
      })

      assert {:closed, _} = Hours.is_open?(restaurant.id, "America/Chicago")
    end

    test "returns closed when no hours set" do
      restaurant = restaurant_fixture()
      assert {:closed, _} = Hours.is_open?(restaurant.id, "America/Chicago")
    end

    test "returns closed when holiday closure exists for today" do
      restaurant = restaurant_fixture()
      now = DateTime.utc_now() |> DateTime.shift_zone!("America/Chicago")
      today = DateTime.to_date(now)
      dow = Date.day_of_week(today, :sunday) - 1

      # Set hours as open
      Hours.upsert_hours(%{
        restaurant_id: restaurant.id,
        day_of_week: dow,
        open_time: ~T[00:00:00],
        close_time: ~T[23:59:00],
        is_closed: false
      })

      # Add closure for today
      Hours.create_closure(%{
        restaurant_id: restaurant.id,
        date: today,
        reason: "Special closure"
      })

      assert {:closed, _} = Hours.is_open?(restaurant.id, "America/Chicago")
    end
  end
end
