defmodule RestaurantDashWeb.WebhookController do
  @moduledoc """
  Stripe webhook receiver.

  POST /api/webhooks/stripe — receives Stripe events and updates order status.

  In production: verifies Stripe-Signature header against STRIPE_WEBHOOK_SECRET.
  In mock/demo mode: accepts raw JSON without signature verification.

  Also handles POST /api/webhooks/stripe/mock for simulating events in dev/test.
  """
  use RestaurantDashWeb, :controller

  alias RestaurantDash.Payments

  @doc "Receive and process a Stripe webhook."
  def stripe(conn, _params) do
    raw_body = conn.assigns[:raw_body] || ""
    sig_header = get_req_header(conn, "stripe-signature") |> List.first()

    case Payments.handle_webhook(raw_body, sig_header) do
      {:ok, _result} ->
        json(conn, %{status: "ok"})

      {:error, :invalid_signature} ->
        conn
        |> put_status(400)
        |> json(%{error: "Invalid signature"})

      {:error, :invalid_json} ->
        conn
        |> put_status(400)
        |> json(%{error: "Invalid JSON"})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: to_string(reason)})
    end
  end

  @doc """
  Mock webhook endpoint for dev/test — simulates Stripe events.
  POST /api/webhooks/stripe/mock with JSON body:
    {"type": "payment_intent.succeeded", "payment_intent_id": "pi_xxx"}
  """
  def mock(conn, params) do
    event_type = params["type"] || "payment_intent.succeeded"
    pi_id = params["payment_intent_id"] || params["id"] || "pi_mock_unknown"

    event =
      case event_type do
        "payment_intent.succeeded" ->
          %{
            "type" => "payment_intent.succeeded",
            "data" => %{"object" => %{"id" => pi_id}}
          }

        "payment_intent.payment_failed" ->
          %{
            "type" => "payment_intent.payment_failed",
            "data" => %{"object" => %{"id" => pi_id}}
          }

        "charge.refunded" ->
          %{
            "type" => "charge.refunded",
            "data" => %{
              "object" => %{
                "id" => "ch_mock_#{pi_id}",
                "payment_intent" => pi_id
              }
            }
          }

        _ ->
          %{"type" => event_type, "data" => %{"object" => %{"id" => pi_id}}}
      end

    raw_body = Jason.encode!(event)

    case Payments.handle_webhook(raw_body, nil) do
      {:ok, result} ->
        json(conn, %{status: "ok", result: to_string(result)})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: to_string(reason)})
    end
  end
end
