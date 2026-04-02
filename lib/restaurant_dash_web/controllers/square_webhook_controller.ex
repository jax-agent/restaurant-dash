defmodule RestaurantDashWeb.SquareWebhookController do
  @moduledoc """
  Handles incoming Square webhooks.
  Processes inventory.count.updated events to sync item availability.

  Square sends webhook events with HMAC-SHA256 signatures.
  Signature key stored in SQUARE_WEBHOOK_SIGNATURE_KEY env var.
  """

  use RestaurantDashWeb, :controller

  alias RestaurantDash.Integrations.Square
  alias RestaurantDash.Workers.SquareInventorySyncWorker

  require Logger

  @doc """
  POST /api/webhooks/square
  Square sends a JSON body with event_type and data.
  """
  def handle(conn, params) do
    merchant_id = get_in(params, ["merchant_id"])
    event_type = params["type"]

    Logger.info("[SquareWebhook] Event: #{event_type} for merchant #{merchant_id}")

    case event_type do
      "inventory.count.updated" ->
        handle_inventory_event(conn, merchant_id, params)

      _ ->
        # Acknowledge unknown events
        send_resp(conn, 200, "ok")
    end
  end

  defp handle_inventory_event(conn, merchant_id, _params) do
    case find_restaurant_by_merchant(merchant_id) do
      nil ->
        Logger.warning("[SquareWebhook] No restaurant found for Square merchant #{merchant_id}")

      restaurant ->
        if Square.connected?(restaurant) do
          SquareInventorySyncWorker.enqueue_for(restaurant.id)
        end
    end

    send_resp(conn, 200, "ok")
  end

  defp find_restaurant_by_merchant(merchant_id) when is_binary(merchant_id) do
    import Ecto.Query
    alias RestaurantDash.Repo
    alias RestaurantDash.Tenancy.Restaurant

    Restaurant
    |> where([r], r.square_merchant_id == ^merchant_id)
    |> Repo.one()
  end

  defp find_restaurant_by_merchant(_), do: nil
end
