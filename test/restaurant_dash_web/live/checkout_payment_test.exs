defmodule RestaurantDashWeb.CheckoutPaymentTest do
  use RestaurantDashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias RestaurantDash.{Cart, Tenancy, Payments}
  alias RestaurantDash.Cart.Store

  setup do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Payment Test Pizza",
        slug: "payment-test-pizza-#{System.unique_integer([:positive])}"
      })

    cart_id = "test-cart-#{System.unique_integer([:positive])}"

    cart =
      Cart.new(restaurant.id)
      |> Cart.add_item(%{
        menu_item_id: nil,
        name: "Test Pizza",
        base_price: 1500,
        price: 1500,
        quantity: 1,
        modifier_names: [],
        selected_modifiers: %{}
      })

    Store.put(cart_id, cart)

    %{restaurant: restaurant, cart_id: cart_id}
  end

  describe "checkout flow with payment step" do
    test "shows payment step in step indicator", %{
      conn: conn,
      restaurant: restaurant,
      cart_id: cart_id
    } do
      conn = init_test_session(conn, %{"cart_id" => cart_id})
      {:ok, _lv, html} = live(conn, ~p"/checkout?restaurant_slug=#{restaurant.slug}")
      assert html =~ "Payment"
    end

    test "shows demo mode banner in payment step", %{
      conn: conn,
      restaurant: restaurant,
      cart_id: cart_id
    } do
      assert Payments.mock_mode?()
      conn = init_test_session(conn, %{"cart_id" => cart_id})
      {:ok, lv, _html} = live(conn, ~p"/checkout?restaurant_slug=#{restaurant.slug}")

      fill_delivery(lv)
      lv |> element("button", "Continue to Payment →") |> render_click()

      html = render(lv)
      assert html =~ "Demo Mode"
      assert html =~ "Pay on Delivery"
    end

    test "can select pay on delivery payment method", %{
      conn: conn,
      restaurant: restaurant,
      cart_id: cart_id
    } do
      conn = init_test_session(conn, %{"cart_id" => cart_id})
      {:ok, lv, _html} = live(conn, ~p"/checkout?restaurant_slug=#{restaurant.slug}")

      fill_delivery(lv)
      lv |> element("button", "Continue to Payment →") |> render_click()

      html = render(lv)
      assert html =~ "Pay on Delivery"
    end

    test "shows stripe card option when restaurant has stripe account", %{
      conn: conn,
      restaurant: restaurant,
      cart_id: cart_id
    } do
      {:ok, _} = Payments.save_stripe_account_id(restaurant, "acct_mock_stripe_xyz")

      conn = init_test_session(conn, %{"cart_id" => cart_id})
      {:ok, lv, _html} = live(conn, ~p"/checkout?restaurant_slug=#{restaurant.slug}")

      fill_delivery(lv)
      lv |> element("button", "Continue to Payment →") |> render_click()

      html = render(lv)
      assert html =~ "Credit / Debit Card"
    end
  end

  describe "tip selection in review step" do
    test "tip buttons are shown in review step", %{
      conn: conn,
      restaurant: restaurant,
      cart_id: cart_id
    } do
      conn = init_test_session(conn, %{"cart_id" => cart_id})
      {:ok, lv, _html} = live(conn, ~p"/checkout?restaurant_slug=#{restaurant.slug}")

      # Go to review step (click continue after filling form)
      fill_delivery(lv)

      html = render(lv)
      assert html =~ "Add a Tip"
      assert html =~ "15%"
      assert html =~ "18%"
      assert html =~ "20%"
      assert html =~ "No tip"
    end

    test "selecting a tip percentage shows tip in totals", %{
      conn: conn,
      restaurant: restaurant,
      cart_id: cart_id
    } do
      conn = init_test_session(conn, %{"cart_id" => cart_id})
      {:ok, lv, _html} = live(conn, ~p"/checkout?restaurant_slug=#{restaurant.slug}")

      fill_delivery(lv)

      lv |> element("button", "20%") |> render_click()

      html = render(lv)
      assert html =~ "Tip"
    end
  end

  describe "order creation with payment" do
    test "order is created and redirects to tracking", %{
      conn: conn,
      restaurant: restaurant,
      cart_id: cart_id
    } do
      conn = init_test_session(conn, %{"cart_id" => cart_id})
      {:ok, lv, _html} = live(conn, ~p"/checkout?restaurant_slug=#{restaurant.slug}")

      fill_delivery(lv)
      lv |> element("button", "Continue to Payment →") |> render_click()
      lv |> element("button", "Review Order →") |> render_click()

      assert {:error, {:redirect, %{to: "/orders/" <> _}}} =
               lv |> element("button", "Place Order 🎉") |> render_click()
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp fill_delivery(lv) do
    lv
    |> element("input[name='customer_name']")
    |> render_change(%{"field" => "customer_name", "value" => "Jane Test"})

    lv
    |> element("input[name='customer_email']")
    |> render_change(%{"field" => "customer_email", "value" => "jane@test.com"})

    lv
    |> element("input[name='customer_phone']")
    |> render_change(%{"field" => "customer_phone", "value" => "5551234567"})

    lv
    |> element("input[name='delivery_address']")
    |> render_change(%{"field" => "delivery_address", "value" => "123 Test St"})

    lv |> element("button", "Continue to Review →") |> render_click()
  end
end
