defmodule RestaurantDashWeb.UserSocket do
  use Phoenix.Socket

  ## Channels
  channel "driver_location:*", RestaurantDashWeb.DriverLocationChannel
  channel "order_tracking:*", RestaurantDashWeb.OrderTrackingChannel

  @impl true
  def connect(params, socket, _connect_info) do
    # Accept both authenticated drivers and anonymous customers
    driver_id =
      case params do
        %{"driver_id" => id} when is_integer(id) -> id
        %{"driver_id" => id} when is_binary(id) -> String.to_integer(id)
        _ -> nil
      end

    {:ok, assign(socket, :driver_id, driver_id)}
  end

  @impl true
  def id(socket) do
    if socket.assigns[:driver_id] do
      "driver_socket:#{socket.assigns.driver_id}"
    else
      nil
    end
  end
end
