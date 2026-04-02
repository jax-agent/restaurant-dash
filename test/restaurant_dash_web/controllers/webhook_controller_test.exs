defmodule RestaurantDashWeb.WebhookControllerTest do
  use RestaurantDashWeb.ConnCase, async: true

  alias RestaurantDash.{Payments, Tenancy, Repo}

  setup do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Webhook Pizza",
        slug: "webhook-pizza-#{System.unique_integer([:positive])}"
      })

    order =
      Repo.insert!(%RestaurantDash.Orders.Order{
        customer_name: "Test",
        customer_email: "t@t.com",
        customer_phone: "555",
        delivery_address: "123 St",
        status: "new",
        restaurant_id: restaurant.id,
        subtotal: 1500,
        tax_amount: 150,
        delivery_fee: 299,
        tip_amount: 0,
        total_amount: 1949,
        items: [],
        payment_status: "pending",
        payment_intent_id: "pi_test_wh_#{System.unique_integer([:positive])}"
      })

    %{restaurant: restaurant, order: order}
  end

  describe "POST /api/webhooks/stripe (mock mode)" do
    test "accepts payment_intent.succeeded and returns 200", %{conn: conn, order: order} do
      body =
        Jason.encode!(%{
          "type" => "payment_intent.succeeded",
          "data" => %{"object" => %{"id" => order.payment_intent_id}}
        })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhooks/stripe", body)

      assert json_response(conn, 200)["status"] == "ok"

      updated = Payments.get_order_by_payment_intent(order.payment_intent_id)
      assert updated.payment_status == "captured"
    end

    test "accepts payment_intent.payment_failed and returns 200", %{conn: conn, order: order} do
      body =
        Jason.encode!(%{
          "type" => "payment_intent.payment_failed",
          "data" => %{"object" => %{"id" => order.payment_intent_id}}
        })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhooks/stripe", body)

      assert json_response(conn, 200)["status"] == "ok"

      updated = Payments.get_order_by_payment_intent(order.payment_intent_id)
      assert updated.payment_status == "failed"
    end

    test "handles charge.refunded event", %{conn: conn, order: order} do
      body =
        Jason.encode!(%{
          "type" => "charge.refunded",
          "data" => %{
            "object" => %{
              "id" => "ch_mock_test",
              "payment_intent" => order.payment_intent_id
            }
          }
        })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhooks/stripe", body)

      assert json_response(conn, 200)["status"] == "ok"

      updated = Payments.get_order_by_payment_intent(order.payment_intent_id)
      assert updated.payment_status == "refunded"
    end

    test "ignores unknown events and returns 200", %{conn: conn} do
      body = Jason.encode!(%{"type" => "some.unknown.event", "data" => %{"object" => %{}}})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhooks/stripe", body)

      assert json_response(conn, 200)["status"] == "ok"
    end

    test "rejects invalid JSON at the Payments layer (unit test)" do
      # Plug.Parsers catches raw malformed JSON before the controller sees it.
      # Test the underlying verify_webhook logic directly:
      assert {:error, :invalid_json} =
               RestaurantDash.Payments.StripeClient.verify_webhook("not json", nil)
    end
  end

  describe "POST /api/webhooks/stripe/mock" do
    test "simulates payment_intent.succeeded", %{conn: conn, order: order} do
      conn =
        post(conn, "/api/webhooks/stripe/mock", %{
          "type" => "payment_intent.succeeded",
          "payment_intent_id" => order.payment_intent_id
        })

      assert json_response(conn, 200)["status"] == "ok"

      updated = Payments.get_order_by_payment_intent(order.payment_intent_id)
      assert updated.payment_status == "captured"
    end

    test "simulates payment_intent.payment_failed", %{conn: conn, order: order} do
      conn =
        post(conn, "/api/webhooks/stripe/mock", %{
          "type" => "payment_intent.payment_failed",
          "payment_intent_id" => order.payment_intent_id
        })

      assert json_response(conn, 200)["status"] == "ok"

      updated = Payments.get_order_by_payment_intent(order.payment_intent_id)
      assert updated.payment_status == "failed"
    end

    test "simulates charge.refunded", %{conn: conn, order: order} do
      conn =
        post(conn, "/api/webhooks/stripe/mock", %{
          "type" => "charge.refunded",
          "payment_intent_id" => order.payment_intent_id
        })

      assert json_response(conn, 200)["status"] == "ok"

      updated = Payments.get_order_by_payment_intent(order.payment_intent_id)
      assert updated.payment_status == "refunded"
    end
  end
end
