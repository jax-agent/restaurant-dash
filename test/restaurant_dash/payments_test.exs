defmodule RestaurantDash.PaymentsTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.{Payments, Tenancy}

  setup do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Test Pizzeria",
        slug: "test-pizzeria-pay"
      })

    %{restaurant: restaurant}
  end

  describe "mock_mode?/0" do
    test "is true in test environment" do
      assert Payments.mock_mode?() == true
    end
  end

  describe "platform fee" do
    test "calculate_platform_fee/1 returns 5% by default" do
      assert Payments.calculate_platform_fee(1000) == 50
      assert Payments.calculate_platform_fee(2500) == 125
    end

    test "platform_fee_percent/0 returns configured value" do
      assert Payments.platform_fee_percent() == 5
    end
  end

  describe "Stripe Connect onboarding" do
    test "begin_stripe_onboarding/3 returns a URL in mock mode", %{restaurant: restaurant} do
      assert {:ok, url} =
               Payments.begin_stripe_onboarding(
                 restaurant,
                 "http://localhost/return",
                 "http://localhost/refresh"
               )

      assert is_binary(url)
    end

    test "begin_stripe_onboarding/3 saves stripe_account_id on restaurant", %{
      restaurant: restaurant
    } do
      {:ok, _url} =
        Payments.begin_stripe_onboarding(
          restaurant,
          "http://localhost/return",
          "http://localhost/refresh"
        )

      updated = Tenancy.get_restaurant!(restaurant.id)
      assert updated.stripe_account_id != nil
      assert String.starts_with?(updated.stripe_account_id, "acct_mock_")
    end

    test "stripe_connected?/1 returns false when no account", %{restaurant: restaurant} do
      refute Payments.stripe_connected?(restaurant)
    end

    test "stripe_connected?/1 returns true when account set", %{restaurant: restaurant} do
      {:ok, updated} = Payments.save_stripe_account_id(restaurant, "acct_mock_xyz")
      assert Payments.stripe_connected?(updated)
    end
  end

  describe "PaymentIntent" do
    test "create_payment_intent/2 returns client_secret and id" do
      order = %{
        subtotal: 2000,
        tip_amount: 0,
        total_amount: 2300,
        tax_amount: 200,
        delivery_fee: 100
      }

      assert {:ok, result} = Payments.create_payment_intent(order)
      assert is_binary(result.client_secret)
      assert is_binary(result.payment_intent_id)
      assert String.starts_with?(result.payment_intent_id, "pi_mock_")
    end
  end

  describe "order payment status" do
    test "update_payment_status/2 updates the order", %{restaurant: restaurant} do
      order = insert_order(restaurant)
      assert {:ok, updated} = Payments.update_payment_status(order, "captured")
      assert updated.payment_status == "captured"
    end

    test "attach_payment_intent/2 sets payment_intent_id and pending status", %{
      restaurant: restaurant
    } do
      order = insert_order(restaurant)
      assert {:ok, updated} = Payments.attach_payment_intent(order, "pi_mock_abc")
      assert updated.payment_intent_id == "pi_mock_abc"
      assert updated.payment_status == "pending"
    end

    test "get_order_by_payment_intent/1 finds order by pi id", %{restaurant: restaurant} do
      order = insert_order(restaurant)
      {:ok, order} = Payments.attach_payment_intent(order, "pi_mock_findme")
      found = Payments.get_order_by_payment_intent("pi_mock_findme")
      assert found.id == order.id
    end
  end

  describe "webhook handling" do
    test "handles payment_intent.succeeded event", %{restaurant: restaurant} do
      order = insert_order(restaurant)
      {:ok, _} = Payments.attach_payment_intent(order, "pi_test_webhook1")

      body =
        Jason.encode!(%{
          "type" => "payment_intent.succeeded",
          "data" => %{"object" => %{"id" => "pi_test_webhook1"}}
        })

      assert {:ok, :processed} = Payments.handle_webhook(body, nil)
      updated = Payments.get_order_by_payment_intent("pi_test_webhook1")
      assert updated.payment_status == "captured"
    end

    test "handles payment_intent.payment_failed event", %{restaurant: restaurant} do
      order = insert_order(restaurant)
      {:ok, _} = Payments.attach_payment_intent(order, "pi_test_webhook2")

      body =
        Jason.encode!(%{
          "type" => "payment_intent.payment_failed",
          "data" => %{"object" => %{"id" => "pi_test_webhook2"}}
        })

      assert {:ok, :processed} = Payments.handle_webhook(body, nil)
      updated = Payments.get_order_by_payment_intent("pi_test_webhook2")
      assert updated.payment_status == "failed"
    end

    test "ignores unknown events" do
      body = Jason.encode!(%{"type" => "some.other.event", "data" => %{"object" => %{}}})
      assert {:ok, :ignored} = Payments.handle_webhook(body, nil)
    end
  end

  describe "refunds" do
    test "refund_order/2 succeeds and updates status to refunded", %{restaurant: restaurant} do
      order = insert_order(restaurant)
      {:ok, order} = Payments.attach_payment_intent(order, "pi_mock_refund1")
      {:ok, order} = Payments.update_payment_status(order, "captured")

      assert {:ok, refunded} = Payments.refund_order(order)
      assert refunded.payment_status == "refunded"
    end

    test "refund_order/2 errors when no payment_intent_id", %{restaurant: restaurant} do
      order = insert_order(restaurant)
      assert {:error, _msg} = Payments.refund_order(order)
    end
  end

  describe "tip calculation" do
    test "calculate_tip/2 returns correct cents" do
      assert Payments.calculate_tip(1000, 15) == 150
      assert Payments.calculate_tip(1000, 18) == 180
      assert Payments.calculate_tip(1000, 20) == 200
      assert Payments.calculate_tip(1000, 0) == 0
    end

    test "tip_options/0 returns expected options" do
      opts = Payments.tip_options()
      labels = Enum.map(opts, fn {label, _} -> label end)
      assert "15%" in labels
      assert "20%" in labels
      assert "No tip" in labels
    end
  end

  # helpers

  defp insert_order(restaurant) do
    {:ok, order} =
      RestaurantDash.Repo.insert(%RestaurantDash.Orders.Order{
        customer_name: "Test Customer",
        customer_email: "test@example.com",
        customer_phone: "555-1234",
        delivery_address: "123 Test St",
        status: "new",
        restaurant_id: restaurant.id,
        subtotal: 2000,
        tax_amount: 200,
        delivery_fee: 300,
        tip_amount: 0,
        total_amount: 2500,
        items: [],
        payment_status: "pending"
      })

    order
  end
end
