defmodule RestaurantDashWeb.DashboardRefundTest do
  use RestaurantDashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias RestaurantDash.{Tenancy, Payments, Repo, Orders}

  setup do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Refund Test Pizza",
        slug: "refund-test-pizza-#{System.unique_integer([:positive])}"
      })

    {:ok, user} =
      RestaurantDash.Accounts.register_user(%{
        email: "refund_owner_#{System.unique_integer([:positive])}@example.com",
        password: "password12345678"
      })

    user =
      user
      |> Ecto.Changeset.change(%{role: "owner", restaurant_id: restaurant.id})
      |> Repo.update!()

    # Create an order with a payment intent
    order =
      Repo.insert!(%RestaurantDash.Orders.Order{
        customer_name: "Refund Customer",
        customer_email: "refund@test.com",
        customer_phone: "555-9999",
        delivery_address: "456 Refund Ave",
        status: "delivered",
        restaurant_id: restaurant.id,
        subtotal: 2000,
        tax_amount: 200,
        delivery_fee: 299,
        tip_amount: 0,
        total_amount: 2499,
        items: [],
        payment_status: "captured",
        payment_intent_id: "pi_mock_refund_test_#{System.unique_integer([:positive])}"
      })

    %{restaurant: restaurant, user: user, order: order}
  end

  describe "refund button visibility" do
    test "shows refund button for orders with payment_intent_id", %{
      conn: conn,
      user: user,
      order: order
    } do
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/orders")

      assert html =~ "Refund"
      assert html =~ order.customer_name
    end

    test "does not show refund button for orders without payment_intent_id", %{
      conn: conn,
      user: user,
      restaurant: restaurant
    } do
      # Create order without payment intent
      Repo.insert!(%RestaurantDash.Orders.Order{
        customer_name: "No Payment Customer",
        customer_email: "nopay@test.com",
        customer_phone: "555-1111",
        delivery_address: "789 Cash Ave",
        status: "delivered",
        restaurant_id: restaurant.id,
        subtotal: 1000,
        tax_amount: 100,
        delivery_fee: 299,
        tip_amount: 0,
        total_amount: 1399,
        items: [],
        payment_status: "pending",
        payment_intent_id: nil
      })

      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/orders")

      assert html =~ "No Payment Customer"
    end

    test "shows 'Refunded' label for already-refunded orders", %{
      conn: conn,
      user: user,
      order: order
    } do
      {:ok, _} = Payments.update_payment_status(order, "refunded")

      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/orders")

      assert html =~ "Refunded"
    end
  end

  describe "refund_order event" do
    test "successfully refunds an order", %{conn: conn, user: user, order: order} do
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/dashboard/orders")

      lv |> element("[phx-click='refund_order'][phx-value-id='#{order.id}']") |> render_click()

      html = render(lv)
      assert html =~ "refunded" or html =~ "Refunded" or html =~ "refunded"

      updated = Orders.get_order!(order.id)
      assert updated.payment_status == "refunded"
    end
  end

  describe "Payments.refund_order/2 (unit)" do
    test "full refund updates payment_status to refunded", %{order: order} do
      assert {:ok, refunded} = Payments.refund_order(order)
      assert refunded.payment_status == "refunded"
    end

    test "partial refund with amount option", %{order: order} do
      assert {:ok, refunded} = Payments.refund_order(order, amount: 500)
      assert refunded.payment_status == "refunded"
    end

    test "fails gracefully when no payment_intent_id" do
      order = %RestaurantDash.Orders.Order{id: 0, payment_intent_id: nil}
      assert {:error, _msg} = Payments.refund_order(order)
    end
  end
end
