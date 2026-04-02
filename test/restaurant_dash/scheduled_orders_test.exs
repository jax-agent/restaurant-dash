defmodule RestaurantDash.ScheduledOrdersTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Orders
  alias RestaurantDash.Orders.Order
  alias RestaurantDash.Tenancy

  defp restaurant_fixture do
    slug = "sched-test-#{System.unique_integer([:positive])}"
    {:ok, r} = Tenancy.create_restaurant(%{name: "Test", slug: slug, timezone: "America/Chicago"})
    r
  end

  defp order_fixture(restaurant_id, attrs \\ %{}) do
    base = %{
      customer_name: "Alice",
      customer_email: "alice@example.com",
      customer_phone: "555-0100",
      delivery_address: "100 Main St",
      restaurant_id: restaurant_id,
      status: "scheduled"
    }

    {:ok, order} =
      %Order{}
      |> Order.cart_order_changeset(Map.merge(base, attrs))
      |> RestaurantDash.Repo.insert()

    order
  end

  describe "validate_scheduled_time/1" do
    test "accepts time 30+ minutes in the future" do
      future = DateTime.utc_now() |> DateTime.add(31 * 60, :second)
      assert :ok = Orders.validate_scheduled_time(future)
    end

    test "rejects time less than 30 minutes away" do
      near = DateTime.utc_now() |> DateTime.add(15 * 60, :second)
      assert {:error, msg} = Orders.validate_scheduled_time(near)
      assert msg =~ "at least 30 minutes"
    end

    test "rejects time more than 7 days away" do
      far = DateTime.utc_now() |> DateTime.add(8 * 24 * 3600, :second)
      assert {:error, msg} = Orders.validate_scheduled_time(far)
      assert msg =~ "7 days"
    end

    test "accepts time exactly at boundary" do
      exactly_30 = DateTime.utc_now() |> DateTime.add(30 * 60 + 1, :second)
      assert :ok = Orders.validate_scheduled_time(exactly_30)
    end
  end

  describe "list_scheduled_orders/1" do
    test "returns only scheduled orders for restaurant" do
      restaurant = restaurant_fixture()
      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      {:ok, sched} =
        %Order{}
        |> Order.cart_order_changeset(%{
          customer_name: "Bob",
          customer_email: "bob@example.com",
          customer_phone: "555-0200",
          delivery_address: "200 Oak Ave",
          restaurant_id: restaurant.id,
          status: "scheduled",
          scheduled_for: future
        })
        |> RestaurantDash.Repo.insert()

      {:ok, normal} =
        %Order{}
        |> Order.cart_order_changeset(%{
          customer_name: "Carol",
          customer_email: "carol@example.com",
          customer_phone: "555-0300",
          delivery_address: "300 Pine St",
          restaurant_id: restaurant.id,
          status: "new"
        })
        |> RestaurantDash.Repo.insert()

      scheduled = Orders.list_scheduled_orders(restaurant.id)
      assert Enum.any?(scheduled, &(&1.id == sched.id))
      refute Enum.any?(scheduled, &(&1.id == normal.id))
    end
  end

  describe "scheduled order status" do
    test "creates order with scheduled status" do
      restaurant = restaurant_fixture()
      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      {:ok, order} =
        %Order{}
        |> Order.cart_order_changeset(%{
          customer_name: "Dave",
          customer_email: "dave@example.com",
          customer_phone: "555-0400",
          delivery_address: "400 Elm Rd",
          restaurant_id: restaurant.id,
          status: "scheduled",
          scheduled_for: future
        })
        |> RestaurantDash.Repo.insert()

      assert order.status == "scheduled"
      assert order.scheduled_for != nil
    end

    test "can transition from scheduled to new (activation)" do
      restaurant = restaurant_fixture()
      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      {:ok, order} =
        %Order{}
        |> Order.cart_order_changeset(%{
          customer_name: "Eve",
          customer_email: "eve@example.com",
          customer_phone: "555-0500",
          delivery_address: "500 Maple Dr",
          restaurant_id: restaurant.id,
          status: "scheduled",
          scheduled_for: future
        })
        |> RestaurantDash.Repo.insert()

      {:ok, activated} = Orders.transition_order(order, "new")
      assert activated.status == "new"
    end
  end

  describe "kitchen visibility" do
    test "kitchen does not see scheduled orders in KDS statuses" do
      restaurant = restaurant_fixture()
      kds_statuses = Order.kds_statuses()
      refute "scheduled" in kds_statuses
    end
  end
end
