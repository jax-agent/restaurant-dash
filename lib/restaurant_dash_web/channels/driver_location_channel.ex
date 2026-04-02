defmodule RestaurantDashWeb.DriverLocationChannel do
  @moduledoc """
  Phoenix Channel for real-time driver GPS tracking.

  Drivers join "driver_location:{driver_id}" and push location updates.
  The channel:
  - Stores location in ETS (fast lookup)
  - Updates driver_profile in DB (persist)
  - Broadcasts to order tracking topic so customers see live position
  """

  use RestaurantDashWeb, :channel

  alias RestaurantDash.Drivers
  alias RestaurantDash.Drivers.LocationCache

  @impl true
  def join("driver_location:" <> driver_id_str, _params, socket) do
    driver_id = String.to_integer(driver_id_str)
    {:ok, assign(socket, :channel_driver_id, driver_id)}
  end

  @impl true
  def handle_in("update_location", params, socket) do
    driver_id = params["driver_id"] || socket.assigns[:channel_driver_id]
    lat = params["lat"]
    lng = params["lng"]
    order_id = params["order_id"]

    if is_number(lat) and is_number(lng) do
      # Store in ETS for fast lookups
      LocationCache.put(driver_id, lat, lng)

      # Async DB update (don't block the channel)
      Task.start(fn ->
        case Drivers.get_profile_by_user_id(driver_id) do
          nil -> :ok
          profile -> Drivers.update_location(profile, lat, lng)
        end
      end)

      # Broadcast to all subscribers of this driver's location
      broadcast!(socket, "location_updated", %{
        driver_id: driver_id,
        lat: lat,
        lng: lng
      })

      # If delivering an order, push to order tracking topic
      if order_id do
        RestaurantDashWeb.Endpoint.broadcast("order_tracking:#{order_id}", "driver_location", %{
          driver_id: driver_id,
          lat: lat,
          lng: lng
        })
      end
    end

    {:noreply, socket}
  end
end
