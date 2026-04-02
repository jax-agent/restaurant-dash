defmodule RestaurantDash.Drivers.DriverRatingsTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.{Orders, Drivers, Repo}

  setup do
    restaurant =
      Repo.insert!(%RestaurantDash.Tenancy.Restaurant{
        name: "Ratings Test",
        slug: "ratings-#{System.unique_integer([:positive])}"
      })

    {:ok, %{user: driver_user, profile: profile}} =
      Drivers.register_driver(%{
        "email" => "ratingdriver_#{System.unique_integer([:positive])}@example.com",
        "password" => "password123456!",
        "vehicle_type" => "car",
        "restaurant_id" => restaurant.id
      })

    order =
      Repo.insert!(%RestaurantDash.Orders.Order{
        customer_name: "Customer",
        customer_email: "cust@example.com",
        customer_phone: "555-9999",
        delivery_address: "1 Rating St",
        status: "delivered",
        restaurant_id: restaurant.id,
        driver_id: driver_user.id,
        items: []
      })

    {:ok, restaurant: restaurant, profile: profile, order: order, driver_user: driver_user}
  end

  describe "submit_driver_rating/3" do
    test "customer can rate driver 1-5", %{order: order} do
      {:ok, updated} = Orders.submit_driver_rating(order, 5, "Excellent!")
      assert updated.driver_rating == 5
      assert updated.driver_rating_comment == "Excellent!"
    end

    test "rating below 1 is invalid", %{order: order} do
      {:error, changeset} = Orders.submit_driver_rating(order, 0)
      assert errors_on(changeset)[:driver_rating]
    end

    test "rating above 5 is invalid", %{order: order} do
      {:error, changeset} = Orders.submit_driver_rating(order, 6)
      assert errors_on(changeset)[:driver_rating]
    end
  end

  describe "get_driver_average_rating/1" do
    test "calculates average across multiple orders", %{
      driver_user: driver_user,
      restaurant: restaurant
    } do
      for rating <- [4, 5, 3] do
        order =
          Repo.insert!(%RestaurantDash.Orders.Order{
            customer_name: "Cust",
            customer_email: "c#{rating}@example.com",
            customer_phone: "555-#{rating}",
            delivery_address: "#{rating} St",
            status: "delivered",
            restaurant_id: restaurant.id,
            driver_id: driver_user.id,
            driver_rating: rating,
            items: []
          })

        order
      end

      {avg, count} = Orders.get_driver_average_rating(driver_user.id)
      assert count == 3
      assert_in_delta avg, 4.0, 0.1
    end

    test "returns nil and 0 when no ratings exist" do
      {avg, count} = Orders.get_driver_average_rating(99_999_888)
      assert avg == nil
      assert count == 0
    end
  end

  describe "low rating alert threshold" do
    test "driver with average < 3.5 is flagged as low-rated", %{
      driver_user: driver_user,
      restaurant: restaurant
    } do
      for rating <- [2, 3, 2] do
        Repo.insert!(%RestaurantDash.Orders.Order{
          customer_name: "Low",
          customer_email: "low#{rating}@example.com",
          customer_phone: "555-#{rating}",
          delivery_address: "#{rating} Low Ave",
          status: "delivered",
          restaurant_id: restaurant.id,
          driver_id: driver_user.id,
          driver_rating: rating,
          items: []
        })
      end

      {avg, _count} = Orders.get_driver_average_rating(driver_user.id)
      assert avg < 3.5, "Driver with avg #{avg} should be flagged"
    end

    test "driver with average >= 3.5 is not flagged", %{
      driver_user: driver_user,
      restaurant: restaurant
    } do
      for rating <- [4, 5, 4] do
        Repo.insert!(%RestaurantDash.Orders.Order{
          customer_name: "Good",
          customer_email: "good#{rating}@example.com",
          customer_phone: "555-#{rating}",
          delivery_address: "#{rating} Good St",
          status: "delivered",
          restaurant_id: restaurant.id,
          driver_id: driver_user.id,
          driver_rating: rating,
          items: []
        })
      end

      {avg, _count} = Orders.get_driver_average_rating(driver_user.id)
      assert avg >= 3.5
    end
  end
end
