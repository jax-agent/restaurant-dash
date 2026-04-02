defmodule RestaurantDashWeb.CheckoutLiveTest do
  use RestaurantDashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias RestaurantDash.{Cart, Tenancy}
  alias RestaurantDash.Cart.Store

  setup do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Test Pizza",
        slug: "test-pizza-#{System.unique_integer([:positive])}",
        is_active: true
      })

    # Build a cart in the store
    cart_id = "test-cart-#{System.unique_integer([:positive])}"

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

    Store.put(cart_id, cart)

    %{restaurant: restaurant, cart_id: cart_id, cart: cart}
  end

  describe "mount" do
    test "redirects to empty state when no cart", %{conn: conn, restaurant: restaurant} do
      {:ok, view, html} =
        live(conn, "/checkout?restaurant_slug=#{restaurant.slug}")

      assert html =~ "cart is empty"
    end

    test "shows delivery form when cart has items", %{
      conn: conn,
      restaurant: restaurant,
      cart_id: cart_id
    } do
      conn = init_test_session(conn, %{"cart_id" => cart_id})

      {:ok, _view, html} = live(conn, "/checkout?restaurant_slug=#{restaurant.slug}")

      assert html =~ "Delivery Details"
      assert html =~ "Full Name"
      assert html =~ "Email"
      assert html =~ "Phone"
      assert html =~ "Delivery Address"
    end
  end

  describe "delivery step validation" do
    test "shows errors for blank fields", %{conn: conn, restaurant: restaurant, cart_id: cart_id} do
      conn = init_test_session(conn, %{"cart_id" => cart_id})

      {:ok, view, _html} = live(conn, "/checkout?restaurant_slug=#{restaurant.slug}")

      html = view |> element("button", "Continue to Review") |> render_click()

      assert html =~ "required"
    end

    test "advances to review step with valid data", %{
      conn: conn,
      restaurant: restaurant,
      cart_id: cart_id
    } do
      conn = init_test_session(conn, %{"cart_id" => cart_id})

      {:ok, view, _html} = live(conn, "/checkout?restaurant_slug=#{restaurant.slug}")

      view
      |> form("#checkout-page", %{
        customer_name: "Jane Doe",
        customer_email: "jane@example.com",
        customer_phone: "555-1234",
        delivery_address: "123 Main St"
      })

      # Fill fields via phx-change events
      view
      |> element("[name=customer_name]")
      |> render_change(%{"field" => "customer_name", "value" => "Jane Doe"})

      view
      |> element("[name=customer_email]")
      |> render_change(%{"field" => "customer_email", "value" => "jane@example.com"})

      view
      |> element("[name=customer_phone]")
      |> render_change(%{"field" => "customer_phone", "value" => "555-1234"})

      view
      |> element("[name=delivery_address]")
      |> render_change(%{"field" => "delivery_address", "value" => "123 Main St"})

      html = view |> element("button", "Continue to Review") |> render_click()

      assert html =~ "Order Summary"
      assert html =~ "Margherita Pizza"
    end
  end

  describe "order review step" do
    test "shows order items and totals", %{conn: conn, restaurant: restaurant, cart_id: cart_id} do
      conn = init_test_session(conn, %{"cart_id" => cart_id})

      {:ok, view, _html} = live(conn, "/checkout?restaurant_slug=#{restaurant.slug}")

      # Advance to review
      view
      |> element("[name=customer_name]")
      |> render_change(%{"field" => "customer_name", "value" => "Bob"})

      view
      |> element("[name=customer_email]")
      |> render_change(%{"field" => "customer_email", "value" => "bob@test.com"})

      view
      |> element("[name=customer_phone]")
      |> render_change(%{"field" => "customer_phone", "value" => "555-0000"})

      view
      |> element("[name=delivery_address]")
      |> render_change(%{"field" => "delivery_address", "value" => "456 Oak Ave"})

      view |> element("button", "Continue to Review") |> render_click()

      html = render(view)
      assert html =~ "Margherita Pizza"
      assert html =~ "Subtotal"
      assert html =~ "Tax"
      assert html =~ "Total"
    end

    test "can go back to delivery step", %{conn: conn, restaurant: restaurant, cart_id: cart_id} do
      conn = init_test_session(conn, %{"cart_id" => cart_id})

      {:ok, view, _html} = live(conn, "/checkout?restaurant_slug=#{restaurant.slug}")

      view
      |> element("[name=customer_name]")
      |> render_change(%{"field" => "customer_name", "value" => "Bob"})

      view
      |> element("[name=customer_email]")
      |> render_change(%{"field" => "customer_email", "value" => "bob@test.com"})

      view
      |> element("[name=customer_phone]")
      |> render_change(%{"field" => "customer_phone", "value" => "555-0000"})

      view
      |> element("[name=delivery_address]")
      |> render_change(%{"field" => "delivery_address", "value" => "456 Oak Ave"})

      view |> element("button", "Continue to Review") |> render_click()

      html = view |> element("button", "← Back") |> render_click()
      assert html =~ "Delivery Details"
    end
  end

  describe "place order" do
    test "creates order and redirects to tracking page", %{
      conn: conn,
      restaurant: restaurant,
      cart_id: cart_id
    } do
      conn = init_test_session(conn, %{"cart_id" => cart_id})

      {:ok, view, _html} = live(conn, "/checkout?restaurant_slug=#{restaurant.slug}")

      # Fill delivery details
      view
      |> element("[name=customer_name]")
      |> render_change(%{"field" => "customer_name", "value" => "Jane"})

      view
      |> element("[name=customer_email]")
      |> render_change(%{"field" => "customer_email", "value" => "jane@test.com"})

      view
      |> element("[name=customer_phone]")
      |> render_change(%{"field" => "customer_phone", "value" => "555-9999"})

      view
      |> element("[name=delivery_address]")
      |> render_change(%{"field" => "delivery_address", "value" => "789 Pine Rd"})

      view |> element("button", "Continue to Review") |> render_click()
      view |> element("button", "Looks Good") |> render_click()

      # Place order — expect redirect
      assert {:error, {:redirect, %{to: "/orders/" <> _}}} =
               view |> element("button", "Place Order") |> render_click()
    end
  end
end
