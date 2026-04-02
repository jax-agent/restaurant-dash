defmodule RestaurantDash.OrdersTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Orders
  alias RestaurantDash.Orders.Order

  describe "create_order/1" do
    test "creates an order with valid attributes" do
      attrs = %{
        customer_name: "Alice Smith",
        items: ["Pizza", "Soda"],
        delivery_address: "123 Main St",
        lat: 37.7749,
        lng: -122.4194
      }

      assert {:ok, %Order{} = order} = Orders.create_order(attrs)
      assert order.customer_name == "Alice Smith"
      assert order.items == ["Pizza", "Soda"]
      assert order.status == "new"
    end

    test "requires customer_name" do
      assert {:error, changeset} = Orders.create_order(%{items: ["Pizza"]})
      assert "can't be blank" in errors_on(changeset).customer_name
    end

    test "requires items" do
      assert {:error, changeset} = Orders.create_order(%{customer_name: "Alice"})
      assert "can't be blank" in errors_on(changeset).items
    end

    test "sets default status to new" do
      {:ok, order} = Orders.create_order(%{customer_name: "Alice", items: ["Pizza"]})
      assert order.status == "new"
    end

    test "rejects invalid status" do
      assert {:error, changeset} =
               Orders.create_order(%{
                 customer_name: "Alice",
                 items: ["Pizza"],
                 status: "invalid_status"
               })

      assert "is invalid" in errors_on(changeset).status
    end
  end

  describe "list_orders/0" do
    test "returns all orders ordered by inserted_at" do
      {:ok, o1} = Orders.create_order(%{customer_name: "Alice", items: ["Pizza"]})
      {:ok, o2} = Orders.create_order(%{customer_name: "Bob", items: ["Pasta"]})

      orders = Orders.list_orders()
      ids = Enum.map(orders, & &1.id)

      assert o1.id in ids
      assert o2.id in ids
    end
  end

  describe "get_order!/1" do
    test "returns the order with given id" do
      {:ok, order} = Orders.create_order(%{customer_name: "Alice", items: ["Pizza"]})
      assert Orders.get_order!(order.id).id == order.id
    end

    test "raises if order not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Orders.get_order!(0)
      end
    end
  end

  describe "transition_order/2" do
    test "transitions order to a new status" do
      {:ok, order} = Orders.create_order(%{customer_name: "Alice", items: ["Pizza"]})
      assert {:ok, updated} = Orders.transition_order(order, "preparing")
      assert updated.status == "preparing"
    end

    test "rejects invalid transition status" do
      {:ok, order} = Orders.create_order(%{customer_name: "Alice", items: ["Pizza"]})
      assert {:error, changeset} = Orders.transition_order(order, "bad_status")
      assert "is invalid" in errors_on(changeset).status
    end
  end

  describe "update_order_position/3" do
    test "updates lat/lng for an order" do
      {:ok, order} =
        Orders.create_order(%{
          customer_name: "Alice",
          items: ["Pizza"],
          status: "out_for_delivery",
          lat: 37.77,
          lng: -122.41
        })

      {:ok, updated} = Orders.update_order_position(order, 37.78, -122.42)
      assert updated.lat == 37.78
      assert updated.lng == -122.42
    end
  end

  describe "count_by_status/0" do
    test "returns a map of status counts" do
      Orders.create_order(%{customer_name: "A", items: ["x"]})
      Orders.create_order(%{customer_name: "B", items: ["x"]})

      counts = Orders.count_by_status()
      assert is_map(counts)
      assert Map.get(counts, "new", 0) >= 2
    end
  end

  describe "items_text virtual field" do
    test "populates items from items_text" do
      attrs = %{
        customer_name: "Alice",
        items_text: "Pizza\nSoda\nBread"
      }

      assert {:ok, order} = Orders.create_order(attrs)
      assert order.items == ["Pizza", "Soda", "Bread"]
    end

    test "ignores blank lines in items_text" do
      attrs = %{
        customer_name: "Alice",
        items_text: "Pizza\n\nSoda\n"
      }

      assert {:ok, order} = Orders.create_order(attrs)
      assert order.items == ["Pizza", "Soda"]
    end
  end
end
