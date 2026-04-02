defmodule RestaurantDash.KitchenTest do
  use RestaurantDash.DataCase, async: false

  alias RestaurantDash.{Accounts, Kitchen, Orders, Tenancy}
  alias RestaurantDash.Orders.Order

  # ─── Fixtures ──────────────────────────────────────────────────────────────

  defp restaurant_fixture do
    unique = System.unique_integer([:positive])

    {:ok, restaurant} =
      Tenancy.create_restaurant(%{name: "Kitchen Test #{unique}", slug: "k-test-#{unique}"})

    restaurant
  end

  defp owner_fixture(restaurant) do
    unique = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.register_user_with_role(%{
        email: "k_owner#{unique}@test.com",
        password: "hello world!",
        role: "owner",
        restaurant_id: restaurant.id
      })

    user
  end

  defp new_order_fixture(restaurant_id) do
    {:ok, order} =
      Orders.create_order(%{
        customer_name: "Test Customer #{System.unique_integer([:positive])}",
        items: ["Burger", "Fries"],
        restaurant_id: restaurant_id
      })

    order
  end

  # ─── list_kds_orders ───────────────────────────────────────────────────────

  describe "list_kds_orders/1" do
    test "returns orders in KDS statuses for the restaurant" do
      restaurant = restaurant_fixture()
      _owner = owner_fixture(restaurant)
      order = new_order_fixture(restaurant.id)

      orders = Kitchen.list_kds_orders(restaurant.id)
      ids = Enum.map(orders, & &1.id)
      assert order.id in ids
    end

    test "does not return orders with non-KDS statuses" do
      restaurant = restaurant_fixture()
      order = new_order_fixture(restaurant.id)
      {:ok, order} = Orders.transition_order(order, "out_for_delivery")

      orders = Kitchen.list_kds_orders(restaurant.id)
      ids = Enum.map(orders, & &1.id)
      refute order.id in ids
    end

    test "does not return orders from other restaurants" do
      r1 = restaurant_fixture()
      r2 = restaurant_fixture()
      order_r1 = new_order_fixture(r1.id)
      _order_r2 = new_order_fixture(r2.id)

      orders = Kitchen.list_kds_orders(r1.id)
      ids = Enum.map(orders, & &1.id)
      assert order_r1.id in ids
      assert length(ids) == 1
    end
  end

  describe "list_kds_orders_grouped/1" do
    test "returns orders grouped by status" do
      restaurant = restaurant_fixture()
      order = new_order_fixture(restaurant.id)

      groups = Kitchen.list_kds_orders_grouped(restaurant.id)
      assert is_map(groups)
      assert Map.has_key?(groups, "new")
      assert order.id in Enum.map(groups["new"], & &1.id)
    end

    test "includes all KDS status keys even when empty" do
      restaurant = restaurant_fixture()
      groups = Kitchen.list_kds_orders_grouped(restaurant.id)

      for status <- Order.kds_statuses() do
        assert Map.has_key?(groups, status), "Missing key: #{status}"
      end
    end
  end

  # ─── accept_order ──────────────────────────────────────────────────────────

  describe "accept_order/1" do
    test "accepts a new order" do
      restaurant = restaurant_fixture()
      order = new_order_fixture(restaurant.id)

      assert {:ok, updated} = Kitchen.accept_order(order)
      assert updated.status == "accepted"
      assert updated.kds_managed == true
      assert updated.accepted_at != nil
    end

    test "returns error for non-new order" do
      restaurant = restaurant_fixture()
      order = new_order_fixture(restaurant.id)
      {:ok, order} = Orders.transition_order(order, "preparing")

      assert {:error, _reason} = Kitchen.accept_order(order)
    end
  end

  # ─── start_preparing ───────────────────────────────────────────────────────

  describe "start_preparing/1" do
    test "moves accepted order to preparing" do
      restaurant = restaurant_fixture()
      order = new_order_fixture(restaurant.id)
      {:ok, order} = Kitchen.accept_order(order)

      assert {:ok, updated} = Kitchen.start_preparing(order)
      assert updated.status == "preparing"
      assert updated.kds_managed == true
      assert updated.preparing_at != nil
    end

    test "returns error for non-accepted order" do
      restaurant = restaurant_fixture()
      order = new_order_fixture(restaurant.id)

      assert {:error, _reason} = Kitchen.start_preparing(order)
    end
  end

  # ─── mark_ready ────────────────────────────────────────────────────────────

  describe "mark_ready/1" do
    test "moves preparing order to ready" do
      restaurant = restaurant_fixture()
      order = new_order_fixture(restaurant.id)
      {:ok, order} = Kitchen.accept_order(order)
      {:ok, order} = Kitchen.start_preparing(order)

      assert {:ok, updated} = Kitchen.mark_ready(order)
      assert updated.status == "ready"
      assert updated.kds_managed == true
      assert updated.ready_at != nil
    end

    test "returns error for non-preparing order" do
      restaurant = restaurant_fixture()
      order = new_order_fixture(restaurant.id)
      {:ok, order} = Kitchen.accept_order(order)

      assert {:error, _reason} = Kitchen.mark_ready(order)
    end
  end

  # ─── reject_order ──────────────────────────────────────────────────────────

  describe "reject_order/1" do
    test "cancels a new order" do
      restaurant = restaurant_fixture()
      order = new_order_fixture(restaurant.id)

      assert {:ok, updated} = Kitchen.reject_order(order)
      assert updated.status == "cancelled"
      assert updated.kds_managed == true
    end

    test "cancels an accepted order" do
      restaurant = restaurant_fixture()
      order = new_order_fixture(restaurant.id)
      {:ok, order} = Kitchen.accept_order(order)

      assert {:ok, updated} = Kitchen.reject_order(order)
      assert updated.status == "cancelled"
    end

    test "cancels a preparing order" do
      restaurant = restaurant_fixture()
      order = new_order_fixture(restaurant.id)
      {:ok, order} = Kitchen.accept_order(order)
      {:ok, order} = Kitchen.start_preparing(order)

      assert {:ok, updated} = Kitchen.reject_order(order)
      assert updated.status == "cancelled"
    end

    test "returns error for delivered order" do
      restaurant = restaurant_fixture()
      order = new_order_fixture(restaurant.id)
      {:ok, order} = Orders.transition_order(order, "preparing")
      {:ok, order} = Orders.transition_order(order, "out_for_delivery")
      {:ok, order} = Orders.transition_order(order, "delivered")

      assert {:error, _reason} = Kitchen.reject_order(order)
    end
  end

  # ─── Full KDS flow ─────────────────────────────────────────────────────────

  describe "full KDS status flow" do
    test "new → accepted → preparing → ready" do
      restaurant = restaurant_fixture()
      order = new_order_fixture(restaurant.id)

      assert {:ok, o1} = Kitchen.accept_order(order)
      assert o1.status == "accepted"
      assert o1.kds_managed == true

      assert {:ok, o2} = Kitchen.start_preparing(o1)
      assert o2.status == "preparing"

      assert {:ok, o3} = Kitchen.mark_ready(o2)
      assert o3.status == "ready"
    end

    test "kds_managed prevents auto-transition interference" do
      restaurant = restaurant_fixture()
      order = new_order_fixture(restaurant.id)

      # Once KDS takes over, kds_managed is true
      {:ok, accepted} = Kitchen.accept_order(order)
      assert accepted.kds_managed == true

      # Status persists in DB
      from_db = Orders.get_order!(accepted.id)
      assert from_db.kds_managed == true
      assert from_db.status == "accepted"
    end
  end

  # ─── Prep time calculation ─────────────────────────────────────────────────

  describe "calculate_prep_time/2" do
    test "calculates base prep time from order items with menu_item preloaded" do
      restaurant = restaurant_fixture()

      order_items = [
        %{quantity: 2, menu_item: %{prep_time_minutes: 8}},
        %{quantity: 1, menu_item: %{prep_time_minutes: 5}}
      ]

      # 2*8 + 1*5 = 21, queue depth = 0, no penalty, max(21, 5) = 21
      result = Kitchen.calculate_prep_time(order_items, restaurant.id)
      assert result == 21
    end

    test "uses default 5 minutes when menu_item not preloaded" do
      restaurant = restaurant_fixture()
      order_items = [%{quantity: 1, menu_item_id: nil}]

      result = Kitchen.calculate_prep_time(order_items, restaurant.id)
      # max(5, 5) + 0 penalty = 5
      assert result == 5
    end

    test "returns at least 5 minutes for tiny orders" do
      restaurant = restaurant_fixture()
      order_items = [%{quantity: 1, menu_item: %{prep_time_minutes: 2}}]

      result = Kitchen.calculate_prep_time(order_items, restaurant.id)
      assert result >= 5
    end

    test "adds queue depth penalty for active orders" do
      restaurant = restaurant_fixture()

      # Create two active (accepted/preparing) orders
      o1 = new_order_fixture(restaurant.id)
      {:ok, o1} = Kitchen.accept_order(o1)
      {:ok, _o1} = Kitchen.start_preparing(o1)

      o2 = new_order_fixture(restaurant.id)
      {:ok, _o2} = Kitchen.accept_order(o2)

      order_items = [%{quantity: 1, menu_item: %{prep_time_minutes: 5}}]
      result = Kitchen.calculate_prep_time(order_items, restaurant.id)

      # max(5, 5) = 5 + 2 active orders * 2 min = 5 + 4 = 9
      assert result > 5
    end

    test "empty order_items returns minimum 5" do
      restaurant = restaurant_fixture()
      result = Kitchen.calculate_prep_time([], restaurant.id)
      assert result == 5
    end
  end

  describe "calculate_base_prep_time/1" do
    test "sums up prep times weighted by quantity" do
      items = [
        %{quantity: 2, menu_item: %{prep_time_minutes: 10}},
        %{quantity: 3, menu_item: %{prep_time_minutes: 5}}
      ]

      assert Kitchen.calculate_base_prep_time(items) == 35
    end
  end

  describe "urgency_color/1" do
    test "returns green for very recent orders" do
      restaurant = restaurant_fixture()
      order = new_order_fixture(restaurant.id)
      assert Kitchen.urgency_color(order) == "green"
    end

    test "returns red for orders over 20 minutes old" do
      old_time = DateTime.add(DateTime.utc_now(), -25 * 60, :second)
      order = %Order{inserted_at: old_time}
      assert Kitchen.urgency_color(order) == "red"
    end

    test "returns yellow for orders 10-20 minutes old" do
      old_time = DateTime.add(DateTime.utc_now(), -15 * 60, :second)
      order = %Order{inserted_at: old_time}
      assert Kitchen.urgency_color(order) == "yellow"
    end
  end

  describe "priority_order?/1" do
    test "non-priority: few items, recent" do
      restaurant = restaurant_fixture()
      order = new_order_fixture(restaurant.id)
      order = %{order | order_items: []}
      refute Kitchen.priority_order?(order)
    end

    test "priority: very old order" do
      old_time = DateTime.add(DateTime.utc_now(), -20 * 60, :second)
      order = %Order{inserted_at: old_time, order_items: []}
      assert Kitchen.priority_order?(order)
    end
  end

  describe "estimated_ready_at/1" do
    test "returns nil when no estimated_prep_minutes" do
      assert Kitchen.estimated_ready_at(%Order{estimated_prep_minutes: nil}) == nil
    end

    test "returns a datetime 30 minutes from inserted_at" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      order = %Order{estimated_prep_minutes: 30, inserted_at: now}
      ready_at = Kitchen.estimated_ready_at(order)
      assert DateTime.diff(ready_at, now) == 30 * 60
    end
  end

  describe "total_item_count/1" do
    test "counts order_items quantities" do
      order = %Order{
        order_items: [
          %{quantity: 2},
          %{quantity: 3}
        ]
      }

      assert Kitchen.total_item_count(order) == 5
    end

    test "counts legacy items array length" do
      order = %Order{
        order_items: [],
        items: ["a", "b", "c"]
      }

      assert Kitchen.total_item_count(order) == 3
    end
  end
end
