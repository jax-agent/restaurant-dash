defmodule RestaurantDash.DeliveryTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Delivery
  alias RestaurantDash.Delivery.DeliveryZone

  # Simple square polygon around San Francisco downtown
  # Corners: NW, NE, SE, SW
  @sf_square [
    [37.785, -122.425],
    [37.785, -122.395],
    [37.765, -122.395],
    [37.765, -122.425]
  ]

  # Oakland — outside the SF square
  @outside_point {37.8044, -122.2712}
  # Inside SF square
  @inside_point {37.775, -122.410}

  setup do
    {:ok, restaurant} =
      RestaurantDash.Repo.insert(%RestaurantDash.Tenancy.Restaurant{
        name: "Test Restaurant",
        slug: "test-delivery-#{System.unique_integer([:positive])}",
        lat: 37.775,
        lng: -122.418,
        fee_mode: "zone",
        base_delivery_fee: 299,
        per_mile_rate: 50,
        free_delivery_threshold: 0,
        driver_base_pay: 500,
        driver_per_mile_pay: 50
      })

    {:ok, restaurant: restaurant}
  end

  describe "point_in_polygon?/3" do
    test "returns true for point inside polygon" do
      {lat, lng} = @inside_point
      assert Delivery.point_in_polygon?(lat, lng, @sf_square)
    end

    test "returns false for point outside polygon" do
      {lat, lng} = @outside_point
      refute Delivery.point_in_polygon?(lat, lng, @sf_square)
    end

    test "returns false for empty polygon" do
      refute Delivery.point_in_polygon?(37.7, -122.4, [])
    end

    test "returns false for polygon with fewer than 3 points" do
      refute Delivery.point_in_polygon?(37.7, -122.4, [[37.7, -122.4], [37.8, -122.4]])
    end

    test "handles triangle" do
      triangle = [[0.0, 0.0], [0.0, 4.0], [4.0, 2.0]]
      assert Delivery.point_in_polygon?(1.0, 2.0, triangle)
      refute Delivery.point_in_polygon?(5.0, 2.0, triangle)
    end
  end

  describe "zone CRUD" do
    test "create_zone/1 creates a zone", %{restaurant: restaurant} do
      {:ok, zone} =
        Delivery.create_zone(%{
          restaurant_id: restaurant.id,
          name: "Downtown",
          polygon: @sf_square,
          delivery_fee: 199,
          min_order: 1000
        })

      assert zone.name == "Downtown"
      assert zone.delivery_fee == 199
      assert zone.polygon == @sf_square
    end

    test "create_zone/1 requires name", %{restaurant: restaurant} do
      {:error, changeset} =
        Delivery.create_zone(%{restaurant_id: restaurant.id, polygon: @sf_square})

      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "list_zones/1 returns zones for restaurant", %{restaurant: restaurant} do
      {:ok, _} =
        Delivery.create_zone(%{
          restaurant_id: restaurant.id,
          name: "Zone A",
          polygon: @sf_square,
          delivery_fee: 0
        })

      zones = Delivery.list_zones(restaurant.id)
      assert length(zones) == 1
    end

    test "update_zone/2 updates a zone", %{restaurant: restaurant} do
      {:ok, zone} =
        Delivery.create_zone(%{
          restaurant_id: restaurant.id,
          name: "Zone X",
          polygon: @sf_square,
          delivery_fee: 100
        })

      {:ok, updated} = Delivery.update_zone(zone, %{delivery_fee: 299})
      assert updated.delivery_fee == 299
    end

    test "delete_zone/1 deletes a zone", %{restaurant: restaurant} do
      {:ok, zone} =
        Delivery.create_zone(%{
          restaurant_id: restaurant.id,
          name: "Temp",
          polygon: @sf_square,
          delivery_fee: 0
        })

      {:ok, _} = Delivery.delete_zone(zone)
      assert Delivery.list_zones(restaurant.id) == []
    end
  end

  describe "find_zone_for_point/3" do
    test "finds the zone containing the point", %{restaurant: restaurant} do
      {:ok, zone} =
        Delivery.create_zone(%{
          restaurant_id: restaurant.id,
          name: "SF Zone",
          polygon: @sf_square,
          delivery_fee: 249
        })

      {lat, lng} = @inside_point
      found = Delivery.find_zone_for_point(restaurant.id, lat, lng)
      assert found.id == zone.id
    end

    test "returns nil when point is outside all zones", %{restaurant: restaurant} do
      {:ok, _} =
        Delivery.create_zone(%{
          restaurant_id: restaurant.id,
          name: "SF Zone",
          polygon: @sf_square,
          delivery_fee: 249
        })

      {lat, lng} = @outside_point
      assert Delivery.find_zone_for_point(restaurant.id, lat, lng) == nil
    end
  end

  describe "calculate_delivery_fee/4 — flat mode" do
    test "returns base fee for flat mode", %{restaurant: restaurant} do
      restaurant = %{restaurant | fee_mode: "flat", base_delivery_fee: 399}
      {:ok, fee} = Delivery.calculate_delivery_fee(restaurant, 37.7, -122.4, 0)
      assert fee == 399
    end

    test "returns 0 when above free delivery threshold", %{restaurant: restaurant} do
      restaurant = %{
        restaurant
        | fee_mode: "flat",
          base_delivery_fee: 399,
          free_delivery_threshold: 2000
      }

      {:ok, fee} = Delivery.calculate_delivery_fee(restaurant, 37.7, -122.4, 2500)
      assert fee == 0
    end

    test "does not apply free delivery when below threshold", %{restaurant: restaurant} do
      restaurant = %{
        restaurant
        | fee_mode: "flat",
          base_delivery_fee: 399,
          free_delivery_threshold: 2000
      }

      {:ok, fee} = Delivery.calculate_delivery_fee(restaurant, 37.7, -122.4, 1500)
      assert fee == 399
    end
  end

  describe "calculate_delivery_fee/4 — zone mode" do
    test "returns zone fee when inside zone", %{restaurant: restaurant} do
      restaurant = %{restaurant | fee_mode: "zone"}

      {:ok, _zone} =
        Delivery.create_zone(%{
          restaurant_id: restaurant.id,
          name: "SF",
          polygon: @sf_square,
          delivery_fee: 249
        })

      {lat, lng} = @inside_point
      {:ok, fee} = Delivery.calculate_delivery_fee(restaurant, lat, lng, 0)
      assert fee == 249
    end

    test "returns error when outside all zones", %{restaurant: restaurant} do
      restaurant = %{restaurant | fee_mode: "zone"}

      {:ok, _zone} =
        Delivery.create_zone(%{
          restaurant_id: restaurant.id,
          name: "SF",
          polygon: @sf_square,
          delivery_fee: 249
        })

      {lat, lng} = @outside_point

      assert {:error, :outside_delivery_area} =
               Delivery.calculate_delivery_fee(restaurant, lat, lng, 0)
    end
  end

  describe "calculate_delivery_fee/4 — distance mode" do
    test "calculates fee based on distance", %{restaurant: restaurant} do
      # Restaurant at SF, delivery 1 km away
      restaurant = %{
        restaurant
        | fee_mode: "distance",
          lat: 37.7749,
          lng: -122.4194,
          base_delivery_fee: 199,
          per_mile_rate: 100
      }

      # Delivery ~1 mile away
      {:ok, fee} = Delivery.calculate_delivery_fee(restaurant, 37.7849, -122.4194, 0)
      # Should be > base fee
      assert fee > 199
    end
  end

  describe "validate_delivery_address/3" do
    test "returns :ok for zone mode when inside zone", %{restaurant: restaurant} do
      restaurant = %{restaurant | fee_mode: "zone"}

      {:ok, _} =
        Delivery.create_zone(%{
          restaurant_id: restaurant.id,
          name: "SF",
          polygon: @sf_square,
          delivery_fee: 0
        })

      {lat, lng} = @inside_point
      assert :ok = Delivery.validate_delivery_address(restaurant, lat, lng)
    end

    test "returns error for zone mode when outside zones", %{restaurant: restaurant} do
      restaurant = %{restaurant | fee_mode: "zone"}

      {:ok, _} =
        Delivery.create_zone(%{
          restaurant_id: restaurant.id,
          name: "SF",
          polygon: @sf_square,
          delivery_fee: 0
        })

      {lat, lng} = @outside_point

      assert {:error, :outside_delivery_area} =
               Delivery.validate_delivery_address(restaurant, lat, lng)
    end

    test "returns :ok for flat mode regardless of location", %{restaurant: restaurant} do
      restaurant = %{restaurant | fee_mode: "flat"}
      assert :ok = Delivery.validate_delivery_address(restaurant, 0.0, 0.0)
    end
  end
end
