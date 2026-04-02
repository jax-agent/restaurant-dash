defmodule RestaurantDash.Drivers.DriverEarningsTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Drivers
  alias RestaurantDash.{Repo, Accounts}

  setup do
    restaurant =
      Repo.insert!(%RestaurantDash.Tenancy.Restaurant{
        name: "Test",
        slug: "earn-test-#{System.unique_integer([:positive])}",
        driver_base_pay: 500,
        driver_per_mile_pay: 50
      })

    {:ok, %{user: user, profile: profile}} =
      Drivers.register_driver(%{
        "email" => "driver_#{System.unique_integer([:positive])}@example.com",
        "password" => "password123456!",
        "vehicle_type" => "car",
        "restaurant_id" => restaurant.id
      })

    order =
      Repo.insert!(%RestaurantDash.Orders.Order{
        customer_name: "John",
        customer_email: "john@test.com",
        customer_phone: "555-0000",
        delivery_address: "456 Oak St",
        status: "delivered",
        restaurant_id: restaurant.id,
        tip_amount: 300,
        items: []
      })

    {:ok, restaurant: restaurant, profile: profile, order: order, user: user}
  end

  describe "record_delivery_earnings/3" do
    test "creates earning record on delivery", %{
      profile: profile,
      order: order,
      restaurant: restaurant
    } do
      {:ok, earning} = Drivers.record_delivery_earnings(profile, order, restaurant)
      assert earning.driver_profile_id == profile.id
      assert earning.order_id == order.id
      assert earning.base_pay == 500
      assert earning.tip_amount == 300
      assert earning.total_earned == 800
    end

    test "does not duplicate earnings for the same order", %{
      profile: profile,
      order: order,
      restaurant: restaurant
    } do
      Drivers.record_delivery_earnings(profile, order, restaurant)
      # Second call should do nothing (on_conflict: :nothing)
      Drivers.record_delivery_earnings(profile, order, restaurant)

      count =
        Repo.aggregate(RestaurantDash.Drivers.DriverEarning, :count, :id)

      assert count == 1
    end

    test "tip_amount is 0 when order has no tip", %{profile: profile, restaurant: restaurant} do
      order_no_tip =
        Repo.insert!(%RestaurantDash.Orders.Order{
          customer_name: "No Tip",
          customer_email: "notip@test.com",
          customer_phone: "555-0001",
          delivery_address: "789 Elm",
          status: "delivered",
          restaurant_id: restaurant.id,
          tip_amount: 0,
          items: []
        })

      {:ok, earning} = Drivers.record_delivery_earnings(profile, order_no_tip, restaurant)
      assert earning.tip_amount == 0
      assert earning.total_earned == 500
    end
  end

  describe "get_today_earnings/1" do
    test "returns today's earnings summary", %{
      profile: profile,
      order: order,
      restaurant: restaurant
    } do
      Drivers.record_delivery_earnings(profile, order, restaurant)
      summary = Drivers.get_today_earnings(profile.id)
      assert summary.total == 800
      assert summary.base == 500
      assert summary.tips == 300
      assert summary.count == 1
    end

    test "returns zeros when no earnings today", %{profile: profile} do
      summary = Drivers.get_today_earnings(profile.id)
      assert summary == %{total: 0, base: 0, tips: 0, count: 0}
    end
  end

  describe "get_week_earnings/1" do
    test "aggregates this week's earnings", %{
      profile: profile,
      order: order,
      restaurant: restaurant
    } do
      Drivers.record_delivery_earnings(profile, order, restaurant)
      summary = Drivers.get_week_earnings(profile.id)
      assert summary.total == 800
      assert summary.count == 1
    end
  end

  describe "get_total_earnings/1" do
    test "returns cumulative totals", %{profile: profile, order: order, restaurant: restaurant} do
      Drivers.record_delivery_earnings(profile, order, restaurant)
      summary = Drivers.get_total_earnings(profile.id)
      assert summary.total == 800
    end
  end

  describe "list_earnings_report/3" do
    test "lists earnings for restaurant", %{
      profile: profile,
      order: order,
      restaurant: restaurant
    } do
      Drivers.record_delivery_earnings(profile, order, restaurant)
      earnings = Drivers.list_earnings_report(restaurant.id)
      assert length(earnings) == 1
      assert hd(earnings).total_earned == 800
    end

    test "returns empty for different restaurant" do
      other_restaurant =
        Repo.insert!(%RestaurantDash.Tenancy.Restaurant{
          name: "Other",
          slug: "other-#{System.unique_integer([:positive])}"
        })

      earnings = Drivers.list_earnings_report(other_restaurant.id)
      assert earnings == []
    end
  end
end
