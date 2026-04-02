defmodule RestaurantDash.Notifications.PreferencesTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Notifications.Preferences
  alias RestaurantDash.Tenancy

  defp restaurant_fixture do
    {:ok, r} =
      Tenancy.create_restaurant(%{
        name: "Prefs Kitchen",
        slug: "prefs-kitchen-#{System.unique_integer([:positive])}",
        address: "1 Test",
        city: "SF",
        state: "CA",
        zip: "94000"
      })

    r
  end

  describe "Preferences.get/1" do
    test "returns default preferences for new restaurant" do
      restaurant = restaurant_fixture()
      prefs = Preferences.get(restaurant)

      assert Map.has_key?(prefs, "new_order")
      assert Map.has_key?(prefs, "payment_alert")
      assert Map.has_key?(prefs, "low_stock_alert")
      assert Map.has_key?(prefs, "driver_alert")
    end

    test "merges stored preferences with defaults" do
      restaurant = restaurant_fixture()

      # Update with partial preferences
      {:ok, updated} =
        Tenancy.update_restaurant(restaurant, %{
          notification_preferences: %{"new_order" => %{"sms" => true}}
        })

      prefs = Preferences.get(updated)

      # Custom sms setting is preserved
      assert prefs["new_order"]["sms"] == true
      # Default email setting is preserved via merge
      assert is_boolean(prefs["new_order"]["email"])
    end
  end

  describe "Preferences.enabled?/3" do
    test "returns false for disabled channel" do
      restaurant = restaurant_fixture()
      # SMS is disabled by default for new_order
      refute Preferences.enabled?(restaurant, "new_order", "sms")
    end

    test "returns true for enabled channel" do
      restaurant = restaurant_fixture()
      # in_app is enabled by default for new_order
      assert Preferences.enabled?(restaurant, "new_order", "in_app")
    end

    test "accepts restaurant_id" do
      restaurant = restaurant_fixture()
      assert is_boolean(Preferences.enabled?(restaurant.id, "new_order", "in_app"))
    end

    test "returns false for unknown restaurant" do
      refute Preferences.enabled?(999_999, "new_order", "sms")
    end
  end

  describe "Preferences.update/2" do
    test "updates preferences for a restaurant" do
      restaurant = restaurant_fixture()

      {:ok, updated} =
        Preferences.update(restaurant, %{
          "new_order" => %{"sms" => true, "email" => true, "in_app" => true}
        })

      prefs = Preferences.get(updated)
      assert prefs["new_order"]["sms"] == true
      assert prefs["new_order"]["email"] == true
      assert prefs["new_order"]["in_app"] == true
    end

    test "updates only specified alert types" do
      restaurant = restaurant_fixture()

      # Default: new_order sms is false
      refute Preferences.enabled?(restaurant, "new_order", "sms")

      {:ok, updated} = Preferences.update(restaurant, %{"new_order" => %{"sms" => true}})

      assert Preferences.enabled?(updated, "new_order", "sms")
      # payment_alert still has defaults
      assert is_boolean(Preferences.enabled?(updated, "payment_alert", "in_app"))
    end
  end

  describe "Preferences.toggle/3" do
    test "toggles a preference on" do
      restaurant = restaurant_fixture()

      # SMS for new_order is off by default
      refute Preferences.enabled?(restaurant, "new_order", "sms")

      {:ok, updated} = Preferences.toggle(restaurant, "new_order", "sms")
      assert Preferences.enabled?(updated, "new_order", "sms")
    end

    test "toggles a preference off" do
      restaurant = restaurant_fixture()

      # in_app for new_order is on by default
      assert Preferences.enabled?(restaurant, "new_order", "in_app")

      {:ok, updated} = Preferences.toggle(restaurant, "new_order", "in_app")
      refute Preferences.enabled?(updated, "new_order", "in_app")
    end

    test "round-trips correctly" do
      restaurant = restaurant_fixture()
      initial = Preferences.enabled?(restaurant, "driver_alert", "sms")

      {:ok, toggled_once} = Preferences.toggle(restaurant, "driver_alert", "sms")
      assert Preferences.enabled?(toggled_once, "driver_alert", "sms") == !initial

      {:ok, toggled_twice} = Preferences.toggle(toggled_once, "driver_alert", "sms")
      assert Preferences.enabled?(toggled_twice, "driver_alert", "sms") == initial
    end
  end

  describe "Preferences metadata" do
    test "alert_types/0 returns all alert types" do
      types = Preferences.alert_types()
      assert "new_order" in types
      assert "payment_alert" in types
      assert "low_stock_alert" in types
      assert "driver_alert" in types
    end

    test "channels/0 returns all channels" do
      channels = Preferences.channels()
      assert "sms" in channels
      assert "email" in channels
      assert "in_app" in channels
    end

    test "label/1 returns human-readable labels" do
      assert Preferences.label("new_order") =~ "New"
      assert Preferences.label("payment_alert") =~ "Payment"
    end

    test "channel_label/1 returns channel labels" do
      assert Preferences.channel_label("sms") == "SMS"
      assert Preferences.channel_label("email") == "Email"
      assert Preferences.channel_label("in_app") == "In-App"
    end
  end
end
