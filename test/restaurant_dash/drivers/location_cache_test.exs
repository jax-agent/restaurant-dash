defmodule RestaurantDash.Drivers.LocationCacheTest do
  use ExUnit.Case, async: false

  alias RestaurantDash.Drivers.LocationCache

  setup do
    # Each test gets a fresh ETS table via the GenServer
    # The GenServer is already started by the application supervisor in test env
    # We just clear state between tests
    LocationCache.clear_all()
    :ok
  end

  describe "put/3 and get/1" do
    test "stores and retrieves driver location" do
      LocationCache.put(42, 37.7749, -122.4194)
      assert {:ok, {37.7749, -122.4194}} = LocationCache.get(42)
    end

    test "returns :not_found for unknown driver" do
      assert :not_found = LocationCache.get(99_999)
    end

    test "overwrites previous location" do
      LocationCache.put(1, 1.0, 2.0)
      LocationCache.put(1, 3.0, 4.0)
      assert {:ok, {3.0, 4.0}} = LocationCache.get(1)
    end
  end

  describe "list_all/0" do
    test "returns all driver locations" do
      LocationCache.put(10, 10.0, 20.0)
      LocationCache.put(11, 11.0, 21.0)
      all = LocationCache.list_all()
      assert {10, 10.0, 20.0} in all
      assert {11, 11.0, 21.0} in all
    end

    test "returns empty list when no drivers" do
      assert LocationCache.list_all() == []
    end
  end

  describe "delete/1" do
    test "removes a driver from cache" do
      LocationCache.put(5, 1.0, 2.0)
      LocationCache.delete(5)
      assert :not_found = LocationCache.get(5)
    end
  end
end
