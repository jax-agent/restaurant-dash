defmodule RestaurantDash.DriverAssignmentTest do
  @moduledoc """
  Tests for Slices 6.3 and 6.6:
  - Order-to-driver assignment
  - Delivery status flow (ready → assigned → picked_up → delivered)
  - PubSub broadcasts
  - Auto-dispatch (Slice 6.4)
  """
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.{Orders, Drivers, Tenancy}
  alias RestaurantDash.Workers.AutoDispatchWorker

  defp unique_email, do: "test#{System.unique_integer()}@example.com"
  defp unique_slug, do: "rest-#{System.unique_integer()}"

  defp create_restaurant(opts \\ []) do
    auto_dispatch = Keyword.get(opts, :auto_dispatch, false)
    {:ok, r} = Tenancy.create_restaurant(%{name: "TestRest", slug: unique_slug()})

    {:ok, r} =
      Tenancy.update_restaurant(r, %{
        auto_dispatch_enabled: auto_dispatch,
        lat: 40.7128,
        lng: -74.0060
      })

    r
  end

  defp create_ready_order(restaurant) do
    {:ok, order} =
      Orders.create_order(%{
        customer_name: "Alice",
        delivery_address: "100 Main St",
        restaurant_id: restaurant.id,
        items: ["Burger"],
        status: "ready"
      })

    order
  end

  defp create_approved_available_driver do
    {:ok, %{user: user, profile: profile}} =
      Drivers.register_driver(%{
        "email" => unique_email(),
        "password" => "securepass1234",
        "name" => "Driver Bob",
        "vehicle_type" => "car"
      })

    {:ok, approved} = Drivers.approve_driver(profile)
    {:ok, available} = Drivers.set_status(approved, "available")
    {:ok, with_loc} = Drivers.update_location(available, 40.7500, -74.0060)
    {user, with_loc}
  end

  # ─── Slice 6.3: Order-to-Driver Assignment ─────────────────────────────────

  describe "Orders.assign_driver/2" do
    test "assigns a driver and sets status to 'assigned'" do
      restaurant = create_restaurant()
      order = create_ready_order(restaurant)
      {user, _profile} = create_approved_available_driver()

      assert {:ok, assigned_order} = Orders.assign_driver(order, user.id)
      assert assigned_order.driver_id == user.id
      assert assigned_order.status == "assigned"
      assert assigned_order.assigned_at != nil
    end

    test "assign_driver sets assigned_at timestamp" do
      restaurant = create_restaurant()
      order = create_ready_order(restaurant)
      {user, _} = create_approved_available_driver()

      {:ok, assigned} = Orders.assign_driver(order, user.id)
      assert %DateTime{} = assigned.assigned_at
    end
  end

  describe "Orders.list_dispatch_queue/1" do
    test "returns only ready orders without a driver" do
      restaurant = create_restaurant()
      order1 = create_ready_order(restaurant)
      _order2 = create_ready_order(restaurant)
      {user, _} = create_approved_available_driver()

      # Assign order1 — it should leave the queue
      {:ok, _} = Orders.assign_driver(order1, user.id)

      queue = Orders.list_dispatch_queue(restaurant.id)
      order_ids = Enum.map(queue, & &1.id)

      refute order1.id in order_ids
    end
  end

  describe "Orders.get_active_delivery/1" do
    test "returns the current active delivery for a driver" do
      restaurant = create_restaurant()
      order = create_ready_order(restaurant)
      {user, _} = create_approved_available_driver()

      {:ok, _assigned} = Orders.assign_driver(order, user.id)

      active = Orders.get_active_delivery(user.id)
      assert active.id == order.id
    end

    test "returns nil when driver has no active delivery" do
      {user, _} = create_approved_available_driver()
      assert Orders.get_active_delivery(user.id) == nil
    end
  end

  # ─── Slice 6.6: Full Delivery Status Chain ─────────────────────────────────

  describe "full delivery flow" do
    test "ready → assigned → picked_up → delivered" do
      restaurant = create_restaurant()
      order = create_ready_order(restaurant)
      {user, profile} = create_approved_available_driver()

      # Step 1: Assign driver
      {:ok, assigned} = Orders.assign_driver(order, user.id)
      assert assigned.status == "assigned"
      assert assigned.driver_id == user.id

      # Step 2: Driver picks up
      {:ok, picked_up} = Orders.update_delivery_status(assigned, "picked_up")
      assert picked_up.status == "picked_up"
      assert picked_up.picked_up_at != nil

      # Step 3: Mark delivered
      {:ok, delivered} = Orders.update_delivery_status(picked_up, "delivered")
      assert delivered.status == "delivered"
      assert delivered.delivered_at != nil

      # Step 4: Driver returns to available
      {:ok, back_available} = Drivers.set_status(profile, "available")
      assert back_available.status == "available"
    end

    test "delivered order shows in driver history" do
      restaurant = create_restaurant()
      order = create_ready_order(restaurant)
      {user, _} = create_approved_available_driver()

      {:ok, assigned} = Orders.assign_driver(order, user.id)
      {:ok, picked_up} = Orders.update_delivery_status(assigned, "picked_up")
      {:ok, _delivered} = Orders.update_delivery_status(picked_up, "delivered")

      history = Orders.list_driver_orders(user.id)
      assert Enum.any?(history, &(&1.status == "delivered"))
    end
  end

  describe "PubSub broadcasts on assignment" do
    test "order_updated is broadcast when driver is assigned" do
      restaurant = create_restaurant()
      Orders.subscribe(restaurant.id)

      order = create_ready_order(restaurant)
      {user, _} = create_approved_available_driver()

      {:ok, _assigned} = Orders.assign_driver(order, user.id)

      assert_receive {:order_updated, updated_order}
      assert updated_order.status == "assigned"
    end

    test "order_updated is broadcast when delivery status changes" do
      restaurant = create_restaurant()
      order = create_ready_order(restaurant)
      {user, _} = create_approved_available_driver()

      {:ok, assigned} = Orders.assign_driver(order, user.id)

      Orders.subscribe(restaurant.id)
      {:ok, _picked_up} = Orders.update_delivery_status(assigned, "picked_up")

      assert_receive {:order_updated, updated}
      assert updated.status == "picked_up"
    end
  end

  # ─── Slice 6.4: Auto-Dispatch ──────────────────────────────────────────────

  describe "AutoDispatchWorker" do
    test "assigns nearest driver when auto-dispatch is enabled" do
      restaurant = create_restaurant(auto_dispatch: true)
      {user, profile} = create_approved_available_driver()

      # Place driver near restaurant
      {:ok, _} = Drivers.update_location(profile, 40.7200, -74.0060)

      order = create_ready_order(restaurant)

      # Perform the job synchronously
      job = %Oban.Job{args: %{"order_id" => order.id}}
      assert :ok = AutoDispatchWorker.perform(job)

      updated_order = Orders.get_order!(order.id)
      assert updated_order.driver_id == user.id
      assert updated_order.status == "assigned"
    end

    test "snoozes when no drivers available" do
      restaurant = create_restaurant(auto_dispatch: true)
      order = create_ready_order(restaurant)

      job = %Oban.Job{args: %{"order_id" => order.id}}
      assert {:snooze, 30} = AutoDispatchWorker.perform(job)
    end

    test "skips when auto-dispatch is disabled" do
      restaurant = create_restaurant(auto_dispatch: false)
      create_approved_available_driver()

      order = create_ready_order(restaurant)

      # schedule_for should return :disabled
      result = AutoDispatchWorker.schedule_for(%{order | status: "ready"})
      assert result == {:ok, :disabled}
    end

    test "no-ops when order already has a driver" do
      restaurant = create_restaurant(auto_dispatch: true)
      order = create_ready_order(restaurant)
      {user, _} = create_approved_available_driver()

      {:ok, assigned_order} = Orders.assign_driver(order, user.id)

      # Running the job on an already-assigned order should be a no-op
      job = %Oban.Job{args: %{"order_id" => assigned_order.id}}
      assert :ok = AutoDispatchWorker.perform(job)
    end

    test "no-ops when order was deleted" do
      job = %Oban.Job{args: %{"order_id" => 999_999}}
      assert :ok = AutoDispatchWorker.perform(job)
    end
  end

  describe "Orders.count_driver_deliveries_today/1" do
    test "counts delivered orders for today" do
      restaurant = create_restaurant()
      order = create_ready_order(restaurant)
      {user, _} = create_approved_available_driver()

      {:ok, assigned} = Orders.assign_driver(order, user.id)
      {:ok, picked_up} = Orders.update_delivery_status(assigned, "picked_up")
      {:ok, _delivered} = Orders.update_delivery_status(picked_up, "delivered")

      count = Orders.count_driver_deliveries_today(user.id)
      assert count >= 1
    end
  end
end
