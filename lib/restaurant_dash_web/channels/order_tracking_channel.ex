defmodule RestaurantDashWeb.OrderTrackingChannel do
  @moduledoc """
  Phoenix Channel for customers to receive live driver location updates.

  Customers join "order_tracking:{order_id}" and receive "driver_location" events
  pushed by the driver's DriverLocationChannel.
  """

  use RestaurantDashWeb, :channel

  @impl true
  def join("order_tracking:" <> _order_id, _params, socket) do
    {:ok, socket}
  end
end
