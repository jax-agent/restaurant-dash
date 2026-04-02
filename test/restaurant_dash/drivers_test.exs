defmodule RestaurantDash.DriversTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Drivers

  # ─── Helpers ───────────────────────────────────────────────────────────────

  defp unique_email, do: "driver#{System.unique_integer()}@example.com"

  defp driver_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "email" => unique_email(),
        "password" => "securepass123",
        "name" => "Test Driver",
        "vehicle_type" => "car",
        "license_plate" => "ABC123",
        "phone" => "555-0100"
      },
      overrides
    )
  end

  # ─── Slice 6.1: Driver Registration & Profile ──────────────────────────────

  describe "register_driver/1" do
    test "creates user with driver role and driver_profile" do
      assert {:ok, %{user: user, profile: profile}} = Drivers.register_driver(driver_attrs())

      assert user.role == "driver"
      assert profile.user_id == user.id
      assert profile.vehicle_type == "car"
      assert profile.is_approved == false
      assert profile.status == "offline"
    end

    test "driver profile starts as unapproved and offline" do
      {:ok, %{profile: profile}} = Drivers.register_driver(driver_attrs())

      assert profile.is_approved == false
      assert profile.is_available == false
      assert profile.status == "offline"
    end

    test "requires email and password" do
      attrs = Map.drop(driver_attrs(), ["email"])
      assert {:error, _changeset} = Drivers.register_driver(attrs)
    end

    test "prevents duplicate email registration" do
      email = unique_email()
      {:ok, _} = Drivers.register_driver(driver_attrs(%{"email" => email}))
      assert {:error, _} = Drivers.register_driver(driver_attrs(%{"email" => email}))
    end
  end

  describe "get_profile_by_user_id/1" do
    test "returns profile for existing driver" do
      {:ok, %{user: user, profile: profile}} = Drivers.register_driver(driver_attrs())
      found = Drivers.get_profile_by_user_id(user.id)
      assert found.id == profile.id
    end

    test "returns nil for non-driver user" do
      assert Drivers.get_profile_by_user_id(999_999) == nil
    end
  end

  describe "list_profiles/0" do
    test "lists all driver profiles with user preloaded" do
      {:ok, %{user: _user1}} = Drivers.register_driver(driver_attrs())
      {:ok, %{user: _user2}} = Drivers.register_driver(driver_attrs())

      profiles = Drivers.list_profiles()
      assert length(profiles) >= 2
      # User should be preloaded
      assert hd(profiles).user.__struct__ == RestaurantDash.Accounts.User
    end
  end

  # ─── Slice 6.1: Approval Flow ──────────────────────────────────────────────

  describe "approve_driver/1 and suspend_driver/1" do
    setup do
      {:ok, %{profile: profile}} = Drivers.register_driver(driver_attrs())
      {:ok, profile: profile}
    end

    test "approve_driver/1 sets is_approved to true", %{profile: profile} do
      assert {:ok, approved} = Drivers.approve_driver(profile)
      assert approved.is_approved == true
    end

    test "suspend_driver/1 sets is_approved to false", %{profile: profile} do
      {:ok, approved} = Drivers.approve_driver(profile)
      assert {:ok, suspended} = Drivers.suspend_driver(approved)
      assert suspended.is_approved == false
    end
  end

  # ─── Slice 6.2: Driver Availability & Status ──────────────────────────────

  describe "set_status/2" do
    test "unapproved driver cannot go available" do
      {:ok, %{profile: profile}} = Drivers.register_driver(driver_attrs())
      assert {:error, _} = Drivers.set_status(profile, "available")
    end

    test "approved driver can go available" do
      {:ok, %{profile: profile}} = Drivers.register_driver(driver_attrs())
      {:ok, approved} = Drivers.approve_driver(profile)

      assert {:ok, updated} = Drivers.set_status(approved, "available")
      assert updated.status == "available"
      assert updated.is_available == true
    end

    test "driver can go offline" do
      {:ok, %{profile: profile}} = Drivers.register_driver(driver_attrs())
      {:ok, approved} = Drivers.approve_driver(profile)
      {:ok, available} = Drivers.set_status(approved, "available")

      assert {:ok, offline} = Drivers.set_status(available, "offline")
      assert offline.status == "offline"
      assert offline.is_available == false
    end

    test "driver can be set to on_delivery" do
      {:ok, %{profile: profile}} = Drivers.register_driver(driver_attrs())
      {:ok, approved} = Drivers.approve_driver(profile)
      {:ok, available} = Drivers.set_status(approved, "available")

      assert {:ok, delivering} = Drivers.set_status(available, "on_delivery")
      assert delivering.status == "on_delivery"
    end

    test "invalid status returns error" do
      {:ok, %{profile: profile}} = Drivers.register_driver(driver_attrs())
      assert {:error, _} = Drivers.set_status(profile, "flying")
    end
  end

  describe "list_available_drivers/0" do
    test "only returns approved + available drivers" do
      {:ok, %{profile: p1}} = Drivers.register_driver(driver_attrs())
      {:ok, %{profile: p2}} = Drivers.register_driver(driver_attrs())

      # Approve and make p1 available
      {:ok, p1_approved} = Drivers.approve_driver(p1)
      {:ok, _p1_available} = Drivers.set_status(p1_approved, "available")

      # p2 stays offline (not approved)
      available = Drivers.list_available_drivers()
      user_ids = Enum.map(available, & &1.user_id)
      assert p1.user_id in user_ids
      refute p2.user_id in user_ids
    end
  end

  describe "update_location/3" do
    test "updates driver's current location" do
      {:ok, %{profile: profile}} = Drivers.register_driver(driver_attrs())

      assert {:ok, updated} = Drivers.update_location(profile, 40.7128, -74.0060)
      assert updated.current_lat == 40.7128
      assert updated.current_lng == -74.0060
    end
  end

  # ─── Slice 6.4: Distance Calculation ──────────────────────────────────────

  describe "haversine_km/4" do
    test "calculates distance between two points" do
      # New York to Los Angeles ≈ 3940 km
      dist = Drivers.haversine_km(40.7128, -74.0060, 34.0522, -118.2437)
      assert_in_delta dist, 3940.0, 50.0
    end

    test "distance from point to itself is zero" do
      dist = Drivers.haversine_km(40.7128, -74.0060, 40.7128, -74.0060)
      assert_in_delta dist, 0.0, 0.001
    end

    test "symmetrical: A to B equals B to A" do
      d1 = Drivers.haversine_km(40.0, -74.0, 41.0, -75.0)
      d2 = Drivers.haversine_km(41.0, -75.0, 40.0, -74.0)
      assert_in_delta d1, d2, 0.001
    end
  end

  describe "find_nearest_driver/2" do
    test "returns nearest available driver" do
      {:ok, %{profile: p1}} = Drivers.register_driver(driver_attrs())
      {:ok, %{profile: p2}} = Drivers.register_driver(driver_attrs())

      {:ok, p1_approved} = Drivers.approve_driver(p1)
      {:ok, p1_available} = Drivers.set_status(p1_approved, "available")
      {:ok, _p1_loc} = Drivers.update_location(p1_available, 40.0, -74.0)

      {:ok, p2_approved} = Drivers.approve_driver(p2)
      {:ok, p2_available} = Drivers.set_status(p2_approved, "available")
      {:ok, _p2_loc} = Drivers.update_location(p2_available, 41.0, -75.0)

      # Search from 40.1, -74.1 — p1 is closer
      nearest = Drivers.find_nearest_driver(40.1, -74.1)
      assert nearest.user_id == p1.user_id
    end

    test "returns nil when no available drivers" do
      assert Drivers.find_nearest_driver(40.0, -74.0) == nil
    end

    test "returns nil when drivers have no location" do
      {:ok, %{profile: profile}} = Drivers.register_driver(driver_attrs())
      {:ok, approved} = Drivers.approve_driver(profile)
      {:ok, _} = Drivers.set_status(approved, "available")

      # No location set — should be excluded
      assert Drivers.find_nearest_driver(40.0, -74.0) == nil
    end
  end
end
