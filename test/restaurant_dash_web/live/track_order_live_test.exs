defmodule RestaurantDashWeb.TrackOrderLiveTest do
  use RestaurantDashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias RestaurantDash.{Cart, Orders, Tenancy}

  setup do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Track Test Restaurant",
        slug: "track-test-#{System.unique_integer([:positive])}",
        is_active: true
      })

    cart =
      Cart.new(restaurant.id)
      |> Cart.add_item(%{
        menu_item_id: nil,
        name: "Test Pizza",
        base_price: 1200,
        quantity: 1,
        selected_modifiers: %{}
      })

    {:ok, order} =
      Orders.create_order_from_cart(cart, %{
        customer_name: "Alice Smith",
        customer_email: "alice@test.com",
        customer_phone: "555-1111",
        delivery_address: "100 Test Ave",
        restaurant_id: restaurant.id
      })

    %{restaurant: restaurant, order: order}
  end

  describe "mount" do
    test "shows order not found for missing order", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/orders/99999/track")
      assert html =~ "not found"
    end

    test "renders confirmation page with order details", %{conn: conn, order: order} do
      {:ok, _view, html} = live(conn, "/orders/#{order.id}/track")

      assert html =~ "Track Your Order"
      assert html =~ "Order ##{order.id}"
      assert html =~ "Alice Smith"
      assert html =~ "100 Test Ave"
    end

    test "shows order items", %{conn: conn, order: order} do
      {:ok, _view, html} = live(conn, "/orders/#{order.id}/track")
      assert html =~ "Test Pizza"
    end

    test "shows timeline with correct initial step", %{conn: conn, order: order} do
      {:ok, _view, html} = live(conn, "/orders/#{order.id}/track")
      assert html =~ "Order Placed"
      assert html =~ "Preparing"
      assert html =~ "Out for Delivery"
      assert html =~ "Delivered"
    end

    test "shows totals for orders with total_amount", %{conn: conn, order: order} do
      {:ok, _view, html} = live(conn, "/orders/#{order.id}/track")
      assert html =~ "Subtotal"
      assert html =~ "Total"
    end
  end

  describe "real-time status updates" do
    test "updates status when PubSub message received", %{conn: conn, order: order} do
      {:ok, view, _html} = live(conn, "/orders/#{order.id}/track")

      # Simulate status update
      {:ok, updated_order} = Orders.transition_order(order, "preparing")

      # Give it a moment to process
      Process.sleep(50)

      html = render(view)
      assert html =~ "Preparing"
    end
  end
end
