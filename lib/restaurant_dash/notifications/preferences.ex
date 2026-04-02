defmodule RestaurantDash.Notifications.Preferences do
  @moduledoc """
  Notification preference management for restaurants.

  Preferences are stored as a JSON map on the restaurant record.
  Structure: %{"alert_type" => %{"channel" => enabled_bool}}

  Example:
    %{
      "new_order" => %{"sms" => false, "email" => true, "in_app" => true},
      "payment_alert" => %{"sms" => false, "email" => true, "in_app" => true},
      ...
    }
  """

  alias RestaurantDash.Tenancy
  alias RestaurantDash.Tenancy.Restaurant

  @alert_types ~w(new_order payment_alert low_stock_alert driver_alert)
  @channels ~w(sms email in_app)

  @default_preferences %{
    "new_order" => %{"sms" => false, "email" => true, "in_app" => true},
    "payment_alert" => %{"sms" => false, "email" => true, "in_app" => true},
    "low_stock_alert" => %{"sms" => false, "email" => false, "in_app" => true},
    "driver_alert" => %{"sms" => false, "email" => false, "in_app" => true}
  }

  def alert_types, do: @alert_types
  def channels, do: @channels
  def default_preferences, do: @default_preferences

  @doc """
  Get notification preferences for a restaurant.
  Merges stored preferences with defaults.
  """
  def get(restaurant) do
    stored = restaurant.notification_preferences || %{}
    deep_merge(@default_preferences, stored)
  end

  @doc """
  Check if a specific channel is enabled for an alert type.
  """
  def enabled?(%Restaurant{} = restaurant, alert_type, channel) do
    prefs = get(restaurant)
    get_in(prefs, [alert_type, channel]) == true
  end

  def enabled?(restaurant_id, alert_type, channel) when is_integer(restaurant_id) do
    case Tenancy.get_restaurant(restaurant_id) do
      nil -> false
      restaurant -> enabled?(restaurant, alert_type, channel)
    end
  end

  @doc """
  Update notification preferences for a restaurant.
  Accepts a map of alert_type => channel => boolean.
  """
  def update(%Restaurant{} = restaurant, preference_changes) do
    current = get(restaurant)
    updated = deep_merge(current, preference_changes)

    Tenancy.update_restaurant(restaurant, %{notification_preferences: updated})
  end

  @doc """
  Toggle a single channel for an alert type.
  """
  def toggle(%Restaurant{} = restaurant, alert_type, channel) do
    current = get(restaurant)
    current_value = get_in(current, [alert_type, channel]) == true
    new_value = !current_value

    updated = put_in(current, [alert_type, channel], new_value)
    Tenancy.update_restaurant(restaurant, %{notification_preferences: updated})
  end

  @doc "Human-readable label for an alert type."
  def label("new_order"), do: "New Order Received"
  def label("payment_alert"), do: "Payment Alerts"
  def label("low_stock_alert"), do: "Low Stock Alerts"
  def label("driver_alert"), do: "Driver Alerts"
  def label(other), do: String.replace(other, "_", " ") |> String.capitalize()

  @doc "Human-readable label for a channel."
  def channel_label("sms"), do: "SMS"
  def channel_label("email"), do: "Email"
  def channel_label("in_app"), do: "In-App"
  def channel_label(other), do: String.capitalize(other)

  # ─── Private ─────────────────────────────────────────────────────────────

  defp deep_merge(base, override) when is_map(base) and is_map(override) do
    Map.merge(base, override, fn _key, base_val, override_val ->
      if is_map(base_val) and is_map(override_val) do
        deep_merge(base_val, override_val)
      else
        override_val
      end
    end)
  end

  defp deep_merge(_base, override), do: override
end
