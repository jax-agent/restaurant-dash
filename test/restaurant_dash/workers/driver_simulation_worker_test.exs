defmodule RestaurantDash.Workers.DriverSimulationWorkerTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Orders
  alias RestaurantDash.Workers.DriverSimulationWorker

  describe "perform/1" do
    test "updates coordinates for out_for_delivery orders with lat/lng" do
      {:ok, order} =
        Orders.create_order(%{
          customer_name: "Bob",
          items: ["Pizza"],
          status: "out_for_delivery",
          lat: 37.7749,
          lng: -122.4194
        })

      job = %Oban.Job{args: %{}}
      assert :ok = DriverSimulationWorker.perform(job)

      updated = Orders.get_order!(order.id)
      # Coordinates should have changed (nudged)
      assert updated.lat != 37.7749 or updated.lng != -122.4194
    end

    test "skips orders without lat/lng" do
      {:ok, order} =
        Orders.create_order(%{
          customer_name: "Bob",
          items: ["Pizza"],
          status: "out_for_delivery"
          # no lat/lng
        })

      job = %Oban.Job{args: %{}}
      assert :ok = DriverSimulationWorker.perform(job)

      updated = Orders.get_order!(order.id)
      assert is_nil(updated.lat)
      assert is_nil(updated.lng)
    end

    test "only updates out_for_delivery orders" do
      {:ok, new_order} =
        Orders.create_order(%{
          customer_name: "Alice",
          items: ["Pizza"],
          status: "new",
          lat: 37.77,
          lng: -122.41
        })

      job = %Oban.Job{args: %{}}
      assert :ok = DriverSimulationWorker.perform(job)

      updated = Orders.get_order!(new_order.id)
      # new order should NOT be updated
      assert updated.lat == 37.77
      assert updated.lng == -122.41
    end
  end
end
