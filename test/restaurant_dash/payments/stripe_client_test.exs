defmodule RestaurantDash.Payments.StripeClientTest do
  use ExUnit.Case, async: true

  alias RestaurantDash.Payments.StripeClient

  describe "mock_mode?/0" do
    test "returns true when no secret key is configured" do
      # In test env, STRIPE_SECRET_KEY is not set, so mock mode should be active
      assert StripeClient.mock_mode?() == true
    end
  end

  describe "create_connect_account/1 (mock mode)" do
    test "returns a fake account ID" do
      assert {:ok, account} = StripeClient.create_connect_account("test@example.com")
      assert String.starts_with?(account["id"], "acct_mock_")
      assert account["email"] == "test@example.com"
    end
  end

  describe "create_account_link/3 (mock mode)" do
    test "returns a URL with mock flag" do
      {:ok, account} = StripeClient.create_connect_account("test@example.com")
      account_id = account["id"]

      assert {:ok, link} =
               StripeClient.create_account_link(
                 account_id,
                 "http://localhost:4000/stripe/return",
                 "http://localhost:4000/stripe/refresh"
               )

      assert is_binary(link["url"])
      assert String.contains?(link["url"], "stripe_mock=true")
    end
  end

  describe "create_payment_intent/3 (mock mode)" do
    test "returns a fake payment intent" do
      assert {:ok, intent} = StripeClient.create_payment_intent(2500)
      assert String.starts_with?(intent["id"], "pi_mock_")
      assert is_binary(intent["client_secret"])
      assert intent["amount"] == 2500
      assert intent["currency"] == "usd"
    end

    test "accepts connect options" do
      assert {:ok, intent} =
               StripeClient.create_payment_intent(5000, "usd",
                 application_fee_amount: 250,
                 transfer_destination: "acct_mock_abc123"
               )

      assert String.starts_with?(intent["id"], "pi_mock_")
    end
  end

  describe "create_refund/2 (mock mode)" do
    test "returns a fake refund" do
      assert {:ok, refund} = StripeClient.create_refund("pi_mock_abc123")
      assert String.starts_with?(refund["id"], "re_mock_")
      assert refund["payment_intent"] == "pi_mock_abc123"
      assert refund["status"] == "succeeded"
    end
  end

  describe "verify_webhook/2 (mock mode)" do
    test "accepts valid JSON in mock mode" do
      body = Jason.encode!(%{"type" => "payment_intent.succeeded", "data" => %{"object" => %{"id" => "pi_123"}}})
      assert {:ok, event} = StripeClient.verify_webhook(body, nil)
      assert event["type"] == "payment_intent.succeeded"
    end

    test "rejects invalid JSON" do
      assert {:error, :invalid_json} = StripeClient.verify_webhook("not json", nil)
    end
  end
end
