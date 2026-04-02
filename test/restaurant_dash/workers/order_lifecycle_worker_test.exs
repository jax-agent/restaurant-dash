defmodule RestaurantDash.Workers.OrderLifecycleWorkerTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Orders
  alias RestaurantDash.Workers.OrderLifecycleWorker

  describe "perform/1 - status transitions" do
    test "transitions order from new to preparing" do
      {:ok, order} = Orders.create_order(%{customer_name: "Alice", items: ["Pizza"]})
      assert order.status == "new"

      job = %Oban.Job{args: %{"order_id" => order.id, "from_status" => "new"}}
      assert :ok = OrderLifecycleWorker.perform(job)

      updated = Orders.get_order!(order.id)
      assert updated.status == "preparing"
    end

    test "transitions order from preparing to out_for_delivery" do
      {:ok, order} = Orders.create_order(%{customer_name: "Alice", items: ["Pizza"]})
      {:ok, order} = Orders.transition_order(order, "preparing")

      job = %Oban.Job{args: %{"order_id" => order.id, "from_status" => "preparing"}}
      assert :ok = OrderLifecycleWorker.perform(job)

      updated = Orders.get_order!(order.id)
      assert updated.status == "out_for_delivery"
    end

    test "transitions order from out_for_delivery to delivered" do
      {:ok, order} = Orders.create_order(%{customer_name: "Alice", items: ["Pizza"]})
      {:ok, order} = Orders.transition_order(order, "preparing")
      {:ok, order} = Orders.transition_order(order, "out_for_delivery")

      job = %Oban.Job{args: %{"order_id" => order.id, "from_status" => "out_for_delivery"}}
      assert :ok = OrderLifecycleWorker.perform(job)

      updated = Orders.get_order!(order.id)
      assert updated.status == "delivered"
    end

    test "does nothing if order status has already changed" do
      {:ok, order} = Orders.create_order(%{customer_name: "Alice", items: ["Pizza"]})
      # Manually advance the order past the expected from_status
      {:ok, order} = Orders.transition_order(order, "preparing")

      # Job still references "new" as from_status (stale job)
      job = %Oban.Job{args: %{"order_id" => order.id, "from_status" => "new"}}
      assert :ok = OrderLifecycleWorker.perform(job)

      # Status should remain preparing, not double-advance
      updated = Orders.get_order!(order.id)
      assert updated.status == "preparing"
    end

    test "returns ok if order has been deleted" do
      job = %Oban.Job{args: %{"order_id" => 999_999, "from_status" => "new"}}
      assert :ok = OrderLifecycleWorker.perform(job)
    end
  end

  describe "perform/1 - kds_managed orders" do
    test "does not auto-transition a kds_managed order" do
      {:ok, order} = Orders.create_order(%{customer_name: "Alice", items: ["Pizza"]})

      # Simulate KDS taking over by setting kds_managed via changeset
      alias RestaurantDash.Repo
      alias RestaurantDash.Orders.Order

      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{kds_managed: true, status: "accepted"})
        |> Repo.update()

      assert order.kds_managed == true
      assert order.status == "accepted"

      # Lifecycle worker should skip this — from_status "new" doesn't match, but
      # even if it did match "accepted", kds_managed would prevent transition
      job = %Oban.Job{args: %{"order_id" => order.id, "from_status" => "accepted"}}
      assert :ok = OrderLifecycleWorker.perform(job)

      # Status should remain accepted (not auto-transitioned)
      updated = Orders.get_order!(order.id)
      assert updated.status == "accepted"
    end
  end

  describe "schedule_for/1" do
    test "schedules a job for a new order" do
      {:ok, order} = Orders.create_order(%{customer_name: "Alice", items: ["Pizza"]})

      assert {:ok, %Oban.Job{}} = OrderLifecycleWorker.schedule_for(order)
    end

    test "does not schedule for non-new orders" do
      {:ok, order} = Orders.create_order(%{customer_name: "Alice", items: ["Pizza"]})
      {:ok, order} = Orders.transition_order(order, "preparing")

      assert {:ok, nil} = OrderLifecycleWorker.schedule_for(order)
    end
  end
end
