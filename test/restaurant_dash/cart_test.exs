defmodule RestaurantDash.CartTest do
  use ExUnit.Case, async: true

  alias RestaurantDash.Cart
  alias RestaurantDash.Cart.CartItem

  describe "new/1" do
    test "creates an empty cart for a restaurant" do
      cart = Cart.new(1)
      assert cart.restaurant_id == 1
      assert cart.items == []
    end
  end

  describe "add_item/2" do
    test "adds a simple item to empty cart" do
      cart = Cart.new(1)

      cart =
        Cart.add_item(cart, %{
          menu_item_id: 10,
          name: "Margherita Pizza",
          base_price: 1200,
          quantity: 1,
          selected_modifiers: %{},
          modifier_names: []
        })

      assert length(cart.items) == 1
      [item] = cart.items
      assert item.menu_item_id == 10
      assert item.name == "Margherita Pizza"
      assert item.quantity == 1
      assert item.line_total == 1200
    end

    test "merges duplicate items (same item, same modifiers)" do
      cart = Cart.new(1)

      cart =
        Cart.add_item(cart, %{
          menu_item_id: 10,
          name: "Garlic Bread",
          base_price: 599,
          quantity: 1,
          selected_modifiers: %{},
          modifier_names: []
        })

      cart =
        Cart.add_item(cart, %{
          menu_item_id: 10,
          name: "Garlic Bread",
          base_price: 599,
          quantity: 1,
          selected_modifiers: %{},
          modifier_names: []
        })

      assert length(cart.items) == 1
      [item] = cart.items
      assert item.quantity == 2
      assert item.line_total == 1198
    end

    test "keeps items separate when modifiers differ" do
      cart = Cart.new(1)

      cart =
        Cart.add_item(cart, %{
          menu_item_id: 10,
          name: "Pizza",
          base_price: 1200,
          quantity: 1,
          selected_modifiers: %{1 => 5},
          modifier_names: [],
          modifier_price_adjustment: 100
        })

      cart =
        Cart.add_item(cart, %{
          menu_item_id: 10,
          name: "Pizza",
          base_price: 1200,
          quantity: 1,
          selected_modifiers: %{1 => 6},
          modifier_names: [],
          modifier_price_adjustment: 200
        })

      assert length(cart.items) == 2
    end

    test "calculates line_total with modifier price adjustment" do
      cart = Cart.new(1)

      cart =
        Cart.add_item(cart, %{
          menu_item_id: 10,
          name: "Pizza",
          base_price: 1200,
          quantity: 2,
          selected_modifiers: %{},
          modifier_names: [],
          modifier_price_adjustment: 150
        })

      [item] = cart.items
      # (1200 + 150) * 2 = 2700
      assert item.line_total == 2700
    end
  end

  describe "remove_item/2" do
    test "removes an item by key" do
      cart = Cart.new(1)

      cart =
        Cart.add_item(cart, %{
          menu_item_id: 10,
          name: "Pizza",
          base_price: 1200,
          quantity: 1,
          selected_modifiers: %{}
        })

      [item] = cart.items
      key = Cart.item_key(item)
      cart = Cart.remove_item(cart, key)
      assert cart.items == []
    end

    test "does not affect other items" do
      cart =
        Cart.new(1)
        |> Cart.add_item(%{
          menu_item_id: 10,
          name: "Pizza",
          base_price: 1200,
          quantity: 1,
          selected_modifiers: %{}
        })
        |> Cart.add_item(%{
          menu_item_id: 20,
          name: "Soda",
          base_price: 299,
          quantity: 1,
          selected_modifiers: %{}
        })

      first_key = Cart.item_key(Enum.at(cart.items, 0))
      cart = Cart.remove_item(cart, first_key)
      assert length(cart.items) == 1
      assert hd(cart.items).menu_item_id == 20
    end
  end

  describe "update_quantity/3" do
    test "updates quantity for a specific item" do
      cart = Cart.new(1)

      cart =
        Cart.add_item(cart, %{
          menu_item_id: 10,
          name: "Pizza",
          base_price: 1200,
          quantity: 1,
          selected_modifiers: %{}
        })

      key = Cart.item_key(hd(cart.items))
      cart = Cart.update_quantity(cart, key, 3)
      [item] = cart.items
      assert item.quantity == 3
      assert item.line_total == 3600
    end

    test "removes item when quantity set to 0" do
      cart = Cart.new(1)

      cart =
        Cart.add_item(cart, %{
          menu_item_id: 10,
          name: "Pizza",
          base_price: 1200,
          quantity: 1,
          selected_modifiers: %{}
        })

      key = Cart.item_key(hd(cart.items))
      cart = Cart.update_quantity(cart, key, 0)
      assert cart.items == []
    end
  end

  describe "calculate_totals/2" do
    test "calculates subtotal, tax, delivery_fee, total" do
      cart =
        Cart.new(1)
        |> Cart.add_item(%{
          menu_item_id: 10,
          name: "Pizza",
          base_price: 1200,
          quantity: 1,
          selected_modifiers: %{}
        })
        |> Cart.add_item(%{
          menu_item_id: 20,
          name: "Soda",
          base_price: 299,
          quantity: 1,
          selected_modifiers: %{}
        })

      totals = Cart.calculate_totals(cart)
      # subtotal: 1200 + 299 = 1499
      assert totals.subtotal == 1499
      # tax: round(1499 * 0.08875) = round(133.04) = 133
      assert totals.tax == round(1499 * 0.08875)
      # delivery_fee: 299 (default)
      assert totals.delivery_fee == 299
      assert totals.tip == 0
      assert totals.total == totals.subtotal + totals.tax + totals.delivery_fee
    end

    test "respects custom tax rate" do
      cart =
        Cart.new(1)
        |> Cart.add_item(%{
          menu_item_id: 10,
          name: "Pizza",
          base_price: 1000,
          quantity: 1,
          selected_modifiers: %{}
        })

      totals = Cart.calculate_totals(cart, tax_rate: 0.1)
      assert totals.tax == 100
    end

    test "respects custom delivery_fee" do
      cart =
        Cart.new(1)
        |> Cart.add_item(%{
          menu_item_id: 10,
          name: "Pizza",
          base_price: 1000,
          quantity: 1,
          selected_modifiers: %{}
        })

      totals = Cart.calculate_totals(cart, delivery_fee: 500)
      assert totals.delivery_fee == 500
    end

    test "empty cart totals all zero" do
      cart = Cart.new(1)
      totals = Cart.calculate_totals(cart)
      assert totals.subtotal == 0
      assert totals.tax == 0
      # delivery_fee still applies
      assert totals.total == totals.delivery_fee
    end
  end

  describe "empty?/1" do
    test "returns true for empty cart" do
      assert Cart.empty?(Cart.new(1))
    end

    test "returns false when items present" do
      cart =
        Cart.new(1)
        |> Cart.add_item(%{
          menu_item_id: 10,
          name: "Pizza",
          base_price: 1200,
          quantity: 1,
          selected_modifiers: %{}
        })

      refute Cart.empty?(cart)
    end
  end

  describe "item_count/1" do
    test "returns sum of all item quantities" do
      cart =
        Cart.new(1)
        |> Cart.add_item(%{
          menu_item_id: 10,
          name: "Pizza",
          base_price: 1200,
          quantity: 2,
          selected_modifiers: %{}
        })
        |> Cart.add_item(%{
          menu_item_id: 20,
          name: "Soda",
          base_price: 299,
          quantity: 3,
          selected_modifiers: %{}
        })

      assert Cart.item_count(cart) == 5
    end
  end
end
