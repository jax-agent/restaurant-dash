defmodule RestaurantDash.Payments.StripeClient do
  @moduledoc """
  Low-level Stripe API client using Req.
  Falls back to mock mode when no STRIPE_SECRET_KEY is configured.
  """

  @stripe_api "https://api.stripe.com/v1"

  def secret_key do
    Application.get_env(:restaurant_dash, :stripe, [])[:secret_key]
  end

  def mock_mode? do
    key = secret_key()
    is_nil(key) or key == "" or key == "sk_test_mock"
  end

  # ── Connect Accounts ────────────────────────────────────────────────────────

  @doc "Create a Stripe Connect Express account."
  def create_connect_account(email) do
    if mock_mode?() do
      fake_id = "acct_mock_" <> random_id(16)
      {:ok, %{"id" => fake_id, "email" => email, "type" => "express"}}
    else
      post("/accounts", %{
        type: "express",
        email: email,
        capabilities: %{
          card_payments: %{requested: true},
          transfers: %{requested: true}
        }
      })
    end
  end

  @doc "Create an account link for Stripe Connect onboarding."
  def create_account_link(account_id, return_url, refresh_url) do
    if mock_mode?() do
      {:ok,
       %{
         "url" => return_url <> "?stripe_mock=true&account_id=#{account_id}",
         "expires_at" => System.os_time(:second) + 3600
       }}
    else
      post("/account_links", %{
        account: account_id,
        refresh_url: refresh_url,
        return_url: return_url,
        type: "account_onboarding"
      })
    end
  end

  @doc "Retrieve a Connect account."
  def retrieve_account(account_id) do
    if mock_mode?() do
      {:ok,
       %{
         "id" => account_id,
         "charges_enabled" => true,
         "payouts_enabled" => true,
         "details_submitted" => true
       }}
    else
      get("/accounts/#{account_id}")
    end
  end

  # ── Payment Intents ──────────────────────────────────────────────────────────

  @doc "Create a PaymentIntent for an order."
  def create_payment_intent(amount, currency \\ "usd", opts \\ []) do
    if mock_mode?() do
      fake_id = "pi_mock_" <> random_id(24)
      fake_secret = fake_id <> "_secret_" <> random_id(24)

      {:ok,
       %{
         "id" => fake_id,
         "client_secret" => fake_secret,
         "amount" => amount,
         "currency" => currency,
         "status" => "requires_payment_method"
       }}
    else
      params =
        %{
          amount: amount,
          currency: currency,
          automatic_payment_methods: %{enabled: true}
        }
        |> merge_connect_opts(opts)

      post("/payment_intents", params)
    end
  end

  @doc "Retrieve a PaymentIntent."
  def retrieve_payment_intent(payment_intent_id) do
    if mock_mode?() do
      {:ok,
       %{
         "id" => payment_intent_id,
         "status" => "succeeded",
         "amount" => 0,
         "currency" => "usd"
       }}
    else
      get("/payment_intents/#{payment_intent_id}")
    end
  end

  # ── Refunds ──────────────────────────────────────────────────────────────────

  @doc "Create a refund for a PaymentIntent."
  def create_refund(payment_intent_id, opts \\ []) do
    if mock_mode?() do
      fake_id = "re_mock_" <> random_id(24)

      {:ok,
       %{
         "id" => fake_id,
         "payment_intent" => payment_intent_id,
         "status" => "succeeded",
         "amount" => Keyword.get(opts, :amount, 0)
       }}
    else
      params =
        %{payment_intent: payment_intent_id}
        |> maybe_put(:amount, Keyword.get(opts, :amount))
        |> maybe_put(:reason, Keyword.get(opts, :reason))

      post("/refunds", params)
    end
  end

  # ── Webhook Verification ─────────────────────────────────────────────────────

  @doc """
  Verify a Stripe webhook signature.
  Returns {:ok, event_map} or {:error, reason}.
  """
  def verify_webhook(raw_body, signature_header) do
    webhook_secret =
      Application.get_env(:restaurant_dash, :stripe, [])[:webhook_secret]

    if mock_mode?() or is_nil(webhook_secret) or webhook_secret == "" do
      # In mock mode: parse raw body as JSON and trust it
      case Jason.decode(raw_body) do
        {:ok, event} -> {:ok, event}
        {:error, _} -> {:error, :invalid_json}
      end
    else
      verify_stripe_signature(raw_body, signature_header, webhook_secret)
    end
  end

  # ── Private Helpers ──────────────────────────────────────────────────────────

  defp post(path, params) do
    Req.post(
      @stripe_api <> path,
      auth: {:basic, secret_key(), ""},
      form: flatten_params(params),
      receive_timeout: 15_000
    )
    |> handle_response()
  end

  defp get(path) do
    Req.get(
      @stripe_api <> path,
      auth: {:basic, secret_key(), ""},
      receive_timeout: 15_000
    )
    |> handle_response()
  end

  defp handle_response({:ok, %{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %{status: _status, body: body}}) do
    error = get_in(body, ["error", "message"]) || "Stripe API error"
    {:error, error}
  end

  defp handle_response({:error, reason}) do
    {:error, inspect(reason)}
  end

  defp merge_connect_opts(params, opts) do
    params
    |> maybe_put_nested(
      [:application_fee_amount],
      Keyword.get(opts, :application_fee_amount)
    )
    |> maybe_put_nested(
      [:transfer_data, :destination],
      Keyword.get(opts, :transfer_destination)
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_nested(map, _path, nil), do: map

  defp maybe_put_nested(map, path, value) do
    put_in(map, Enum.map(path, &Access.key(&1, %{})), value)
  end

  # Stripe API uses form-encoded with nested params as key[nested]=value
  defp flatten_params(map, prefix \\ nil) do
    Enum.flat_map(map, fn {k, v} ->
      key = if prefix, do: "#{prefix}[#{k}]", else: to_string(k)

      case v do
        %{} -> flatten_params(v, key)
        _ -> [{key, to_string(v)}]
      end
    end)
  end

  defp random_id(len) do
    :crypto.strong_rand_bytes(len)
    |> Base.encode16(case: :lower)
    |> binary_part(0, len)
  end

  defp verify_stripe_signature(raw_body, sig_header, secret) do
    # Stripe signature format: t=timestamp,v1=signature
    with {:ok, parts} <- parse_sig_header(sig_header),
         timestamp = Map.get(parts, "t"),
         signature = Map.get(parts, "v1"),
         true <- not is_nil(timestamp) and not is_nil(signature),
         expected = compute_signature(raw_body, timestamp, secret),
         true <- Plug.Crypto.secure_compare(expected, signature) do
      case Jason.decode(raw_body) do
        {:ok, event} -> {:ok, event}
        {:error, _} -> {:error, :invalid_json}
      end
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp parse_sig_header(header) when is_binary(header) do
    parts =
      header
      |> String.split(",")
      |> Enum.reduce(%{}, fn part, acc ->
        case String.split(part, "=", parts: 2) do
          [k, v] -> Map.put(acc, k, v)
          _ -> acc
        end
      end)

    {:ok, parts}
  end

  defp parse_sig_header(_), do: {:error, :invalid_header}

  defp compute_signature(raw_body, timestamp, secret) do
    payload = "#{timestamp}.#{raw_body}"
    :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
  end
end
