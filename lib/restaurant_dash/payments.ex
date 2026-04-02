defmodule RestaurantDash.Payments do
  @moduledoc """
  Payments context for RestaurantDash.

  Handles Stripe Connect onboarding, PaymentIntent lifecycle,
  tip handling, and refunds. Operates in mock mode when no
  STRIPE_SECRET_KEY is configured (safe for demo/dev).
  """

  alias RestaurantDash.Repo
  alias RestaurantDash.Payments.StripeClient
  alias RestaurantDash.Orders.Order
  import Ecto.Query

  # ── Config Helpers ───────────────────────────────────────────────────────────

  @doc "Returns true when running without real Stripe credentials."
  def mock_mode?, do: StripeClient.mock_mode?()

  @doc "Platform fee percentage (default 5%)."
  def platform_fee_percent do
    Application.get_env(:restaurant_dash, :stripe, [])[:platform_fee_percent] || 5
  end

  @doc "Calculate platform fee in cents."
  def calculate_platform_fee(subtotal_cents) do
    round(subtotal_cents * platform_fee_percent() / 100)
  end

  # ── Stripe Connect Onboarding ────────────────────────────────────────────────

  @doc """
  Begin Stripe Connect onboarding for a restaurant.
  Returns {:ok, onboarding_url} or {:error, reason}.
  """
  def begin_stripe_onboarding(restaurant, return_url, refresh_url) do
    with {:ok, account} <- StripeClient.create_connect_account(nil),
         account_id = account["id"],
         {:ok, _} <- save_stripe_account_id(restaurant, account_id),
         {:ok, link} <- StripeClient.create_account_link(account_id, return_url, refresh_url) do
      {:ok, link["url"]}
    end
  end

  @doc """
  Check if a restaurant's Stripe account is fully connected and enabled.
  """
  def stripe_connected?(restaurant) do
    case restaurant.stripe_account_id do
      nil -> false
      "" -> false
      _id -> true
    end
  end

  @doc """
  Fetch live status of a restaurant's Stripe account.
  Returns {:ok, %{charges_enabled: bool, payouts_enabled: bool}} or {:error, reason}.
  """
  def get_stripe_account_status(restaurant) do
    case restaurant.stripe_account_id do
      nil ->
        {:ok, %{charges_enabled: false, payouts_enabled: false, connected: false}}

      account_id ->
        case StripeClient.retrieve_account(account_id) do
          {:ok, acct} ->
            {:ok,
             %{
               connected: true,
               charges_enabled: acct["charges_enabled"] || false,
               payouts_enabled: acct["payouts_enabled"] || false
             }}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc "Persist a Stripe account ID on the restaurant record."
  def save_stripe_account_id(restaurant, account_id) do
    restaurant
    |> Ecto.Changeset.change(%{stripe_account_id: account_id})
    |> Repo.update()
  end

  # ── PaymentIntent ────────────────────────────────────────────────────────────

  @doc """
  Create a Stripe PaymentIntent for an order.

  Options:
    - :stripe_account_id — restaurant's connected account
    - :application_fee_amount — platform cut in cents (auto-calculated if not provided)
    - :tip_amount — tip in cents (added to total)

  Returns {:ok, %{client_secret: ..., payment_intent_id: ...}} or {:error, reason}.
  """
  def create_payment_intent(order, opts \\ []) do
    subtotal = order.subtotal || 0
    tip = Keyword.get(opts, :tip_amount, order.tip_amount || 0)
    total = order.total_amount + tip

    stripe_account_id = Keyword.get(opts, :stripe_account_id)

    connect_opts =
      if stripe_account_id do
        fee = calculate_platform_fee(subtotal)

        [
          application_fee_amount: fee,
          transfer_destination: stripe_account_id
        ]
      else
        []
      end

    case StripeClient.create_payment_intent(total, "usd", connect_opts) do
      {:ok, intent} ->
        {:ok,
         %{
           client_secret: intent["client_secret"],
           payment_intent_id: intent["id"]
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Order Payment Status ─────────────────────────────────────────────────────

  @doc "Mark an order's payment_intent_id."
  def attach_payment_intent(order, payment_intent_id) do
    order
    |> Ecto.Changeset.change(%{payment_intent_id: payment_intent_id, payment_status: "pending"})
    |> Repo.update()
  end

  @doc "Update an order's payment status."
  def update_payment_status(order, status)
      when status in ~w(pending authorized captured failed refunded) do
    order
    |> Ecto.Changeset.change(%{payment_status: status})
    |> Repo.update()
  end

  @doc "Find an order by payment_intent_id."
  def get_order_by_payment_intent(payment_intent_id) do
    Repo.one(
      from o in Order,
        where: o.payment_intent_id == ^payment_intent_id
    )
  end

  # ── Webhooks ─────────────────────────────────────────────────────────────────

  @doc """
  Process a raw Stripe webhook.
  Returns {:ok, :processed} or {:error, reason}.
  """
  def handle_webhook(raw_body, sig_header) do
    with {:ok, event} <- StripeClient.verify_webhook(raw_body, sig_header) do
      process_event(event)
    end
  end

  defp process_event(%{"type" => "payment_intent.succeeded", "data" => %{"object" => pi}}) do
    update_order_for_payment_intent(pi["id"], "captured")
    {:ok, :processed}
  end

  defp process_event(%{"type" => "payment_intent.payment_failed", "data" => %{"object" => pi}}) do
    update_order_for_payment_intent(pi["id"], "failed")
    {:ok, :processed}
  end

  defp process_event(%{"type" => "charge.refunded", "data" => %{"object" => charge}}) do
    pi_id = charge["payment_intent"]
    if pi_id, do: update_order_for_payment_intent(pi_id, "refunded")
    {:ok, :processed}
  end

  defp process_event(_event), do: {:ok, :ignored}

  defp update_order_for_payment_intent(payment_intent_id, status) do
    case get_order_by_payment_intent(payment_intent_id) do
      nil -> :noop
      order -> update_payment_status(order, status)
    end
  end

  # ── Refunds ──────────────────────────────────────────────────────────────────

  @doc """
  Refund an order. Pass :amount in cents for partial refund, omit for full refund.
  Returns {:ok, order} or {:error, reason}.
  """
  def refund_order(order, opts \\ []) do
    case order.payment_intent_id do
      nil ->
        {:error, "No payment intent on this order"}

      pi_id ->
        refund_opts =
          []
          |> maybe_add(:amount, Keyword.get(opts, :amount))
          |> maybe_add(:reason, Keyword.get(opts, :reason, "requested_by_customer"))

        case StripeClient.create_refund(pi_id, refund_opts) do
          {:ok, _refund} ->
            update_payment_status(order, "refunded")

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp maybe_add(list, _key, nil), do: list
  defp maybe_add(list, key, val), do: Keyword.put(list, key, val)

  # ── Tip Calculation ──────────────────────────────────────────────────────────

  @doc "Calculate tip amount in cents for a given percentage."
  def calculate_tip(subtotal_cents, percent) when is_number(percent) do
    round(subtotal_cents * percent / 100)
  end

  @doc "Suggested tip options as {label, percent} pairs."
  def tip_options do
    [
      {"15%", 15},
      {"18%", 18},
      {"20%", 20},
      {"Custom", :custom},
      {"No tip", 0}
    ]
  end
end
