defmodule RestaurantDashWeb.CloverWebhookController do
  @moduledoc """
  Handles incoming Clover webhooks.
  Currently handles inventory change events to sync item availability.
  """

  use RestaurantDashWeb, :controller

  alias RestaurantDash.Workers.CloverInventorySyncWorker

  require Logger

  @doc """
  POST /api/webhooks/clover
  Clover sends webhooks with event type and merchant ID.
  """
  def handle(conn, %{"merchants" => merchants} = _params) do
    Enum.each(merchants, fn {merchant_id, events} ->
      Logger.info("[CloverWebhook] Received #{length(events)} events for merchant #{merchant_id}")

      has_inventory_event = Enum.any?(events, &inventory_event?/1)

      if has_inventory_event do
        # Find restaurant by merchant_id and trigger sync
        case find_restaurant_by_merchant(merchant_id) do
          nil ->
            Logger.warning("[CloverWebhook] No restaurant found for merchant #{merchant_id}")

          restaurant ->
            CloverInventorySyncWorker.enqueue_for(restaurant.id)
        end
      end
    end)

    send_resp(conn, 200, "ok")
  end

  def handle(conn, _params) do
    send_resp(conn, 200, "ok")
  end

  defp inventory_event?(%{"type" => type}) when is_binary(type) do
    String.contains?(type, ["INVENTORY", "ITEM"])
  end

  defp inventory_event?(_), do: false

  defp find_restaurant_by_merchant(merchant_id) do
    import Ecto.Query
    alias RestaurantDash.Repo
    alias RestaurantDash.Tenancy.Restaurant

    Restaurant
    |> where([r], r.clover_merchant_id == ^merchant_id)
    |> Repo.one()
  end
end
