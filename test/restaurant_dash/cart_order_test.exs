defmodule RestaurantDash.CartOrderTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.{Cart, Orders, Tenancy}
  alias RestaurantDash.Orders.{Order, OrderItem}

  setup do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Test Restaurant",
        slug: "test-rest-#{System.unique_integer([:positive])}",
        is_active: true
      })

    %{restaurant: restaurant}
  end

  describe "create_order_from_cart/2" do
    test "creates order with order_items from cart", %{restaurant: restaurant} do
      cart =
        Cart.new(restaurant.id)
        |> Cart.add_item(%{
          menu_item_id: nil,
          name: "Margherita Pizza",
          base_price: 1200,
          quantity: 2,
          selected_modifiers: %{},
          modifier_names: []
        })
        |> Cart.add_item(%{
          menu_item_id: nil,
          name: "Garlic Bread",
          base_price: 599,
          quantity: 1,
          selected_modifiers: %{},
          modifier_names: []
        })

      attrs = %{
        customer_name: "Jane Doe",
        customer_email: "jane@example.com",
        customer_phone: "555-1234",
        delivery_address: "123 Main St",
        restaurant_id: restaurant.id
      }

      assert {:ok, order} = Orders.create_order_from_cart(cart, attrs)
      assert order.customer_name == "Jane Doe"
      assert order.customer_email == "jane@example.com"
      assert order.customer_phone == "555-1234"
      assert order.status == "new"
      assert order.restaurant_id == restaurant.id

      # Totals
      assert order.subtotal == 1200 * 2 + 599
      assert order.tax_amount > 0
      assert order.delivery_fee == 299
      assert order.total_amount == order.subtotal + order.tax_amount + order.delivery_fee

      # Order items
      assert length(order.order_items) == 2

      pizza = Enum.find(order.order_items, &(&1.name == "Margherita Pizza"))
      assert pizza.quantity == 2
      assert pizza.unit_price == 1200
      assert pizza.line_total == 2400

      bread = Enum.find(order.order_items, &(&1.name == "Garlic Bread"))
      assert bread.quantity == 1
      assert bread.unit_price == 599
      assert bread.line_total == 599
    end

    test "order items include modifier info", %{restaurant: restaurant} do
      cart =
        Cart.new(restaurant.id)
        |> Cart.add_item(%{
          menu_item_id: nil,
          name: "Pizza",
          base_price: 1200,
          quantity: 1,
          selected_modifiers: %{1 => 5},
          modifier_names: [{"Extra Cheese", 150}],
          modifier_price_adjustment: 150
        })

      attrs = %{
        customer_name: "Bob",
        customer_email: "bob@example.com",
        customer_phone: "555-0000",
        delivery_address: "456 Oak Ave",
        restaurant_id: restaurant.id
      }

      assert {:ok, order} = Orders.create_order_from_cart(cart, attrs)
      [item] = order.order_items
      assert item.unit_price == 1350
      assert item.line_total == 1350
      modifiers = Jason.decode!(item.modifiers_json)
      assert [%{"name" => "Extra Cheese", "price_adjustment" => 150}] = modifiers
    end

    test "validates required customer fields", %{restaurant: restaurant} do
      cart =
        Cart.new(restaurant.id)
        |> Cart.add_item(%{
          menu_item_id: nil,
          name: "Pizza",
          base_price: 1200,
          quantity: 1,
          selected_modifiers: %{}
        })

      assert {:error, changeset} =
               Orders.create_order_from_cart(cart, %{
                 customer_name: "Bob",
                 restaurant_id: restaurant.id
               })

      assert "can't be blank" in errors_on(changeset).customer_email
      assert "can't be blank" in errors_on(changeset).customer_phone
    end
  end

  describe "get_order_with_items/1" do
    test "returns order with preloaded order_items", %{restaurant: restaurant} do
      cart =
        Cart.new(restaurant.id)
        |> Cart.add_item(%{
          menu_item_id: nil,
          name: "Soda",
          base_price: 299,
          quantity: 1,
          selected_modifiers: %{}
        })

      {:ok, order} =
        Orders.create_order_from_cart(cart, %{
          customer_name: "Alice",
          customer_email: "alice@test.com",
          customer_phone: "555-5555",
          delivery_address: "789 Pine Rd",
          restaurant_id: restaurant.id
        })

      fetched = Orders.get_order_with_items!(order.id)
      assert fetched.id == order.id
      assert length(fetched.order_items) == 1
    end
  end
end
