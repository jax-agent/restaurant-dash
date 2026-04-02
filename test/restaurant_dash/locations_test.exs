defmodule RestaurantDash.LocationsTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Locations
  alias RestaurantDash.Locations.Location
  alias RestaurantDash.Tenancy

  defp restaurant_fixture do
    slug = "loc-test-#{System.unique_integer([:positive])}"
    {:ok, r} = Tenancy.create_restaurant(%{name: "Test", slug: slug, timezone: "America/Chicago"})
    r
  end

  defp location_attrs(restaurant_id, attrs \\ %{}) do
    Map.merge(
      %{
        restaurant_id: restaurant_id,
        name: "Main Location",
        address: "100 Main St",
        city: "Chicago",
        state: "IL",
        zip: "60601",
        lat: 41.8781,
        lng: -87.6298
      },
      attrs
    )
  end

  describe "create_location/1" do
    test "creates a location" do
      restaurant = restaurant_fixture()

      assert {:ok, %Location{} = loc} =
               Locations.create_location(location_attrs(restaurant.id))

      assert loc.name == "Main Location"
      assert loc.address == "100 Main St"
    end

    test "first location becomes primary" do
      restaurant = restaurant_fixture()
      {:ok, loc} = Locations.create_location(location_attrs(restaurant.id))
      assert loc.is_primary == true
    end

    test "requires name and address" do
      restaurant = restaurant_fixture()

      assert {:error, changeset} =
               Locations.create_location(%{restaurant_id: restaurant.id})

      assert %{name: _, address: _} = errors_on(changeset)
    end
  end

  describe "list_locations/1" do
    test "returns all locations for restaurant" do
      restaurant = restaurant_fixture()
      {:ok, loc1} = Locations.create_location(location_attrs(restaurant.id, %{name: "Loc A"}))
      {:ok, loc2} = Locations.create_location(location_attrs(restaurant.id, %{name: "Loc B"}))
      locs = Locations.list_locations(restaurant.id)
      ids = Enum.map(locs, & &1.id)
      assert loc1.id in ids
      assert loc2.id in ids
    end

    test "does not return other restaurants' locations" do
      r1 = restaurant_fixture()
      r2 = restaurant_fixture()
      {:ok, loc} = Locations.create_location(location_attrs(r1.id))
      locs = Locations.list_locations(r2.id)
      refute Enum.any?(locs, &(&1.id == loc.id))
    end
  end

  describe "update_location/2" do
    test "updates a location" do
      restaurant = restaurant_fixture()
      {:ok, loc} = Locations.create_location(location_attrs(restaurant.id))
      assert {:ok, updated} = Locations.update_location(loc, %{name: "Updated"})
      assert updated.name == "Updated"
    end
  end

  describe "deactivate_location/1" do
    test "deactivates a location" do
      restaurant = restaurant_fixture()
      {:ok, loc} = Locations.create_location(location_attrs(restaurant.id))
      assert {:ok, deactivated} = Locations.deactivate_location(loc)
      assert deactivated.is_active == false
    end
  end

  describe "set_primary/1" do
    test "sets a location as primary and clears others" do
      restaurant = restaurant_fixture()
      {:ok, loc1} = Locations.create_location(location_attrs(restaurant.id, %{name: "First"}))
      {:ok, loc2} = Locations.create_location(location_attrs(restaurant.id, %{name: "Second"}))

      # loc1 should be primary (first created)
      assert loc1.is_primary == true

      # Set loc2 as primary
      {:ok, new_primary} = Locations.set_primary(loc2)
      assert new_primary.is_primary == true

      # Reload loc1 — should no longer be primary
      reloaded_loc1 = Locations.get_location!(loc1.id)
      assert reloaded_loc1.is_primary == false
    end
  end

  describe "find_nearest/3" do
    test "returns nearest location" do
      restaurant = restaurant_fixture()

      # Chicago
      {:ok, chicago} =
        Locations.create_location(
          location_attrs(restaurant.id, %{name: "Chicago", lat: 41.8781, lng: -87.6298})
        )

      # New York
      {:ok, _ny} =
        Locations.create_location(
          location_attrs(restaurant.id, %{name: "New York", lat: 40.7128, lng: -74.006})
        )

      # Query from near Chicago (Naperville, IL)
      nearest = Locations.find_nearest(restaurant.id, 41.7508, -88.1535)
      assert nearest.id == chicago.id
    end

    test "returns nil when no locations have coordinates" do
      restaurant = restaurant_fixture()

      Locations.create_location(
        location_attrs(restaurant.id, %{name: "No Coords", lat: nil, lng: nil})
      )

      result = Locations.find_nearest(restaurant.id, 41.8781, -87.6298)
      assert is_nil(result)
    end
  end

  describe "haversine_distance/2" do
    test "calculates approximate distance between two points" do
      # Chicago to New York ~ 1147 km
      dist = Locations.haversine_distance({41.8781, -87.6298}, {40.7128, -74.006})
      assert_in_delta dist, 1147.0, 50.0
    end

    test "same point is zero distance" do
      dist = Locations.haversine_distance({41.8781, -87.6298}, {41.8781, -87.6298})
      assert_in_delta dist, 0.0, 0.001
    end
  end
end
