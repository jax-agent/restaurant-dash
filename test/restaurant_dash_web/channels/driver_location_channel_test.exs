defmodule RestaurantDashWeb.DriverLocationChannelTest do
  use RestaurantDashWeb.ChannelCase

  alias RestaurantDashWeb.UserSocket
  alias RestaurantDash.Drivers.LocationCache

  setup do
    LocationCache.clear_all()
    :ok
  end

  describe "join driver_location channel" do
    test "driver can join their own location channel" do
      driver_id = 999
      {:ok, socket} = connect(UserSocket, %{"driver_id" => driver_id})
      {:ok, _, _socket} = subscribe_and_join(socket, "driver_location:#{driver_id}", %{})
    end

    test "push location update stores in ETS and broadcasts" do
      driver_id = 998
      {:ok, socket} = connect(UserSocket, %{"driver_id" => driver_id})
      {:ok, _, socket} = subscribe_and_join(socket, "driver_location:#{driver_id}", %{})

      push(socket, "update_location", %{
        "driver_id" => driver_id,
        "lat" => 37.7749,
        "lng" => -122.4194
      })

      assert_broadcast "location_updated", %{driver_id: ^driver_id, lat: 37.7749, lng: -122.4194}
      assert {:ok, {37.7749, -122.4194}} = LocationCache.get(driver_id)
    end

    test "broadcast to order tracking topic when order_id provided" do
      driver_id = 997
      order_id = 1001

      {:ok, socket} = connect(UserSocket, %{"driver_id" => driver_id})
      {:ok, _, socket} = subscribe_and_join(socket, "driver_location:#{driver_id}", %{})

      # Customer subscribes to order tracking
      RestaurantDashWeb.Endpoint.subscribe("order_tracking:#{order_id}")

      push(socket, "update_location", %{
        "driver_id" => driver_id,
        "lat" => 37.77,
        "lng" => -122.41,
        "order_id" => order_id
      })

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "order_tracking:1001",
        event: "driver_location",
        payload: %{lat: 37.77, lng: -122.41}
      }
    end
  end

  describe "join order_tracking channel" do
    test "customer can join order tracking channel" do
      {:ok, socket} = connect(UserSocket, %{})
      {:ok, _, _socket} = subscribe_and_join(socket, "order_tracking:123", %{})
    end
  end
end
